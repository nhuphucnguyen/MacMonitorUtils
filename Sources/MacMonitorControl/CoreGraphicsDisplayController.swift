import CoreGraphics
import Darwin
import Foundation
import OSLog

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
  private var builtinWasDisabledByThisApp = false
  private var recoveryFailureWasReported = false
  private var recoveryCheckGeneration: UInt = 0
  private var safetyWatchdog: DispatchSourceTimer?
  private var knownActiveExternalDisplayIDs = Set<CGDirectDisplayID>()

  private let frameworkHandle: UnsafeMutableRawPointer?
  private let configureDisplayEnabled: ConfigureDisplayEnabledFunction?
  private let logger = Logger(
    subsystem: "local.mac-monitor-control",
    category: "DisplayRecovery"
  )

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
    safetyWatchdog != nil
  }

  func snapshot() -> DisplaySnapshot {
    let onlineIDs = onlineDisplayIDs()
    if let currentBuiltinID = onlineIDs.first(where: isBuiltinDisplay) {
      knownBuiltinDisplayID = currentBuiltinID
    }

    let activeIDs = activeDisplayIDs()
    let builtinID = knownBuiltinDisplayID
    let activeExternalIDs = activeIDs.filter { !isBuiltinDisplay($0) }
    knownActiveExternalDisplayIDs = Set(activeExternalIDs)

    return DisplaySnapshot(
      builtinDisplayID: builtinID,
      builtinIsActive: builtinID.map(activeIDs.contains) ?? false,
      activeExternalDisplayCount: activeExternalIDs.count
    )
  }

  func setBuiltinDisplayEnabled(_ enabled: Bool, force: Bool = false) throws {
    let currentSnapshot = snapshot()

    guard let builtinDisplayID = currentSnapshot.builtinDisplayID else {
      throw DisplayControlError.noBuiltinDisplay
    }

    if !force && currentSnapshot.builtinIsActive == enabled {
      if enabled {
        builtinWasDisabledByThisApp = false
      }
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

    builtinWasDisabledByThisApp = !enabled
    recoveryFailureWasReported = false
    log("Built-in display was turned \(enabled ? "on" : "off").")
  }

  func restoreBuiltinDisplayIfNeeded() throws {
    let currentSnapshot = snapshot()
    if currentSnapshot.builtinDisplayID != nil
      && (builtinWasDisabledByThisApp || !currentSnapshot.builtinIsActive)
    {
      try setBuiltinDisplayEnabled(true, force: builtinWasDisabledByThisApp)
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
    startSafetyWatchdog()
    log(
      isMonitoring
        ? "Display callback and safety watchdog are active."
        : "Display callback registration failed; safety watchdog is active."
    )
    return isSafetyRestoreActive
  }

  func stopMonitoring() {
    recoveryCheckGeneration &+= 1
    safetyWatchdog?.cancel()
    safetyWatchdog = nil
    if isMonitoring {
      CGDisplayRemoveReconfigurationCallback(
        displayReconfigurationCallback,
        Unmanaged.passUnretained(self).toOpaque()
      )
    }
    isMonitoring = false
    changeHandler = nil
  }

  private func startSafetyWatchdog() {
    guard safetyWatchdog == nil else { return }

    let watchdog = DispatchSource.makeTimerSource(queue: .main)
    watchdog.schedule(
      deadline: .now() + 1,
      repeating: 1,
      leeway: .milliseconds(200)
    )
    watchdog.setEventHandler { [weak self] in
      self?.safetyWatchdogDidFire()
    }
    safetyWatchdog = watchdog
    watchdog.resume()
  }

  private func safetyWatchdogDidFire() {
    guard !isApplyingConfiguration else { return }

    let currentSnapshot = snapshot()
    guard shouldAttemptSafetyRestore(for: currentSnapshot) else {
      recoveryFailureWasReported = false
      return
    }

    log("Safety watchdog detected that no external display remains.")
    let recoveryError = attemptSafetyRestore()
    changeHandler?(snapshot(), recoveryError)
  }

  fileprivate func scheduleDisplayConfigurationChecks() {
    guard isMonitoring else { return }

    recoveryCheckGeneration &+= 1
    let generation = recoveryCheckGeneration

    // Display removal is asynchronous inside WindowServer. Check more than once
    // so a dock or cable disconnect is still caught if the first snapshot is stale.
    for delay in [0.15, 0.75, 2.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self,
          self.isMonitoring,
          self.recoveryCheckGeneration == generation
        else { return }

        self.displayConfigurationDidChange()
      }
    }
  }

  fileprivate func displayWasReconfigured(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags
  ) {
    let displayWasRemoved = flags.rawValue & (1 << 5) != 0
    let removedDisplayWasExternal = displayID != knownBuiltinDisplayID

    if displayWasRemoved && removedDisplayWasExternal {
      knownActiveExternalDisplayIDs.remove(displayID)

      if builtinWasDisabledByThisApp && knownActiveExternalDisplayIDs.isEmpty {
        // Do this before waiting for WindowServer's active-display list to
        // settle. A Mac with no active outputs can enter display sleep before
        // the watchdog gets its next timer event.
        log("The last known external display was removed; restoring immediately.")
        let recoveryError = attemptSafetyRestore()
        changeHandler?(snapshot(), recoveryError)
      }
    }

    scheduleDisplayConfigurationChecks()
  }

  fileprivate func displayConfigurationDidChange() {
    guard !isApplyingConfiguration else { return }

    let currentSnapshot = snapshot()
    let recoveryError: Error?

    if shouldAttemptSafetyRestore(for: currentSnapshot) {
      log("Display callback detected that no external display remains.")
      recoveryError = attemptSafetyRestore()
    } else {
      recoveryFailureWasReported = false
      recoveryError = nil
    }

    changeHandler?(snapshot(), recoveryError)
  }

  private func attemptSafetyRestore() -> Error? {
    do {
      // Force the private enable call because CGGetActiveDisplayList can briefly
      // claim the panel is active even while WindowServer still has it disabled.
      try setBuiltinDisplayEnabled(true, force: true)
      recoveryFailureWasReported = false
      log("Safety restore turned the built-in display on.")
      return nil
    } catch {
      log("Safety restore failed: \(error.localizedDescription)")
      guard !recoveryFailureWasReported else { return nil }
      recoveryFailureWasReported = true
      return error
    }
  }

  private func shouldAttemptSafetyRestore(for snapshot: DisplaySnapshot) -> Bool {
    builtinWasDisabledByThisApp
      && snapshot.builtinDisplayID != nil
      && snapshot.activeExternalDisplayCount == 0
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

  private func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")
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

  DispatchQueue.main.async {
    controller.displayWasReconfigured(displayID: displayID, flags: flags)
  }
}
