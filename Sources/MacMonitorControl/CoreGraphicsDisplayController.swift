import CoreGraphics
import Darwin
import Foundation

final class CoreGraphicsDisplayController {
  typealias ChangeHandler = (_ snapshot: DisplaySnapshot, _ recoveryError: Error?) -> Void

  private typealias ConfigureDisplayEnabledFunction =
    @convention(c) (
      OpaquePointer,
      CGDirectDisplayID,
      Bool
    ) -> Int32

  private static let coreGraphicsPath =
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

  private var knownBuiltinDisplayID: CGDirectDisplayID?
  private var changeHandler: ChangeHandler?
  private var isMonitoring = false
  private var isApplyingConfiguration = false

  private let frameworkHandle: UnsafeMutableRawPointer?
  private let configureDisplayEnabled: ConfigureDisplayEnabledFunction?

  init() {
    let handle = dlopen(Self.coreGraphicsPath, RTLD_NOW | RTLD_LOCAL)
    frameworkHandle = handle

    if let handle, let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") {
      configureDisplayEnabled = unsafeBitCast(
        symbol,
        to: ConfigureDisplayEnabledFunction.self
      )
    } else {
      configureDisplayEnabled = nil
    }

    knownBuiltinDisplayID = onlineDisplayIDs().first(where: isBuiltinDisplay)
  }

  deinit {
    stopMonitoring()
    if let frameworkHandle {
      dlclose(frameworkHandle)
    }
  }

  var isControlAvailable: Bool {
    configureDisplayEnabled != nil
  }

  var isSafetyRestoreActive: Bool {
    isMonitoring
  }

  func snapshot() -> DisplaySnapshot {
    let onlineIDs = onlineDisplayIDs()
    if let currentBuiltinID = onlineIDs.first(where: isBuiltinDisplay) {
      knownBuiltinDisplayID = currentBuiltinID
    }

    let activeIDs = activeDisplayIDs()
    let builtinID = knownBuiltinDisplayID

    return DisplaySnapshot(
      builtinDisplayID: builtinID,
      builtinIsActive: builtinID.map(activeIDs.contains) ?? false,
      activeExternalDisplayCount: activeIDs.filter { !isBuiltinDisplay($0) }.count
    )
  }

  func setBuiltinDisplayEnabled(_ enabled: Bool) throws {
    let currentSnapshot = snapshot()

    guard let builtinDisplayID = currentSnapshot.builtinDisplayID else {
      throw DisplayControlError.noBuiltinDisplay
    }

    if currentSnapshot.builtinIsActive == enabled {
      return
    }

    if !enabled && currentSnapshot.activeExternalDisplayCount == 0 {
      throw DisplayControlError.noExternalDisplay
    }

    guard let configureDisplayEnabled else {
      throw DisplayControlError.privateAPINotAvailable
    }

    var configuration: CGDisplayConfigRef?
    let beginResult = CGBeginDisplayConfiguration(&configuration)
    guard beginResult == .success, let configuration else {
      throw DisplayControlError.beginConfiguration(beginResult)
    }

    isApplyingConfiguration = true
    defer { isApplyingConfiguration = false }

    let configureResult = configureDisplayEnabled(
      configuration,
      builtinDisplayID,
      enabled
    )

    guard configureResult == CGError.success.rawValue else {
      CGCancelDisplayConfiguration(configuration)
      throw DisplayControlError.configureDisplay(configureResult)
    }

    let completeResult = CGCompleteDisplayConfiguration(configuration, .forSession)
    guard completeResult == .success else {
      throw DisplayControlError.completeConfiguration(completeResult)
    }
  }

  func restoreBuiltinDisplayIfNeeded() throws {
    let currentSnapshot = snapshot()
    if currentSnapshot.builtinDisplayID != nil && !currentSnapshot.builtinIsActive {
      try setBuiltinDisplayEnabled(true)
    }
  }

  @discardableResult
  func startMonitoring(changeHandler: @escaping ChangeHandler) -> Bool {
    self.changeHandler = changeHandler
    guard !isMonitoring else { return true }

    let result = CGDisplayRegisterReconfigurationCallback(
      displayReconfigurationCallback,
      Unmanaged.passUnretained(self).toOpaque()
    )

    isMonitoring = result == .success
    if !isMonitoring {
      self.changeHandler = nil
    }
    return isMonitoring
  }

  func stopMonitoring() {
    if isMonitoring {
      CGDisplayRemoveReconfigurationCallback(
        displayReconfigurationCallback,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }
    isMonitoring = false
    changeHandler = nil
  }

  fileprivate func displayConfigurationDidChange() {
    guard !isApplyingConfiguration else { return }

    let currentSnapshot = snapshot()
    var recoveryError: Error?

    if currentSnapshot.builtinDisplayID != nil,
      !currentSnapshot.builtinIsActive,
      currentSnapshot.activeExternalDisplayCount == 0
    {
      do {
        try setBuiltinDisplayEnabled(true)
      } catch {
        recoveryError = error
      }
    }

    changeHandler?(snapshot(), recoveryError)
  }

  private func activeDisplayIDs() -> [CGDirectDisplayID] {
    displayIDs(using: CGGetActiveDisplayList)
  }

  private func onlineDisplayIDs() -> [CGDirectDisplayID] {
    displayIDs(using: CGGetOnlineDisplayList)
  }

  private func displayIDs(
    using function: (
      UInt32,
      UnsafeMutablePointer<CGDirectDisplayID>?,
      UnsafeMutablePointer<UInt32>?
    ) -> CGError
  ) -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard function(0, nil, &count) == .success, count > 0 else {
      return []
    }

    var displays = Array(repeating: CGDirectDisplayID(0), count: Int(count))
    let result = displays.withUnsafeMutableBufferPointer { buffer in
      function(count, buffer.baseAddress, &count)
    }

    guard result == .success else { return [] }
    return Array(displays.prefix(Int(count)))
  }

  private func isBuiltinDisplay(_ displayID: CGDirectDisplayID) -> Bool {
    CGDisplayIsBuiltin(displayID) != 0
  }
}

private func displayReconfigurationCallback(
  _ displayID: CGDirectDisplayID,
  _ flags: CGDisplayChangeSummaryFlags,
  _ userInfo: UnsafeMutableRawPointer?
) {
  guard let userInfo else { return }
  let controller = Unmanaged<CoreGraphicsDisplayController>
    .fromOpaque(userInfo)
    .takeUnretainedValue()

  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
    controller.displayConfigurationDidChange()
  }
}
