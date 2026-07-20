import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let displayController = CoreGraphicsDisplayController()
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let statusMenu = NSMenu()
  private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

  func applicationDidFinishLaunching(_ notification: Notification) {
    ProcessInfo.processInfo.disableAutomaticTermination(
      "The display safety watchdog must remain active."
    )
    ProcessInfo.processInfo.disableSuddenTermination()

    observeSleepAndWake()
    configureStatusItem()
    displayController.startMonitoring { [weak self] _, _ in
      guard let self else { return }
      self.refreshStatusIcon()
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    do {
      try displayController.restoreBuiltinDisplayIfNeeded()
      return .terminateNow
    } catch {
      showError(title: "Could not restore the built-in display", error: error)
      return .terminateCancel
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    workspaceNotificationCenter.removeObserver(self)
    displayController.stopMonitoring()
  }

  func menuWillOpen(_ menu: NSMenu) {
    rebuildMenu()
  }

  @objc private func toggleBuiltinDisplay() {
    let currentSnapshot = displayController.snapshot()

    do {
      try displayController.setBuiltinDisplayEnabled(!currentSnapshot.builtinIsActive)
      refreshStatusIcon()
    } catch {
      showError(title: "Display change failed", error: error)
    }
  }

  @objc private func refreshDisplays() {
    refreshStatusIcon()
    rebuildMenu()
  }

  @objc private func quitApplication() {
    NSApp.terminate(nil)
  }

  @objc private func systemWillSleep(_ notification: Notification) {
    displayController.suspendAutomaticRecovery(reason: "the Mac is preparing to sleep")
  }

  @objc private func screenDidSleep(_ notification: Notification) {
    displayController.suspendAutomaticRecovery(reason: "the screen is asleep")
  }

  @objc private func sessionDidResignActive(_ notification: Notification) {
    displayController.suspendAutomaticRecovery(reason: "the login session is inactive")
  }

  @objc private func systemDidWake(_ notification: Notification) {
    displayController.resumeAutomaticRecovery(after: 5, reason: "the Mac woke")
  }

  @objc private func screenDidWake(_ notification: Notification) {
    displayController.resumeAutomaticRecovery(after: 3, reason: "the screen woke")
  }

  @objc private func sessionDidBecomeActive(_ notification: Notification) {
    displayController.resumeAutomaticRecovery(after: 2, reason: "the login session became active")
  }

  private func configureStatusItem() {
    statusMenu.delegate = self
    statusItem.menu = statusMenu

    if let button = statusItem.button {
      button.toolTip = "Mac Monitor Control"
    }

    refreshStatusIcon()
    rebuildMenu()
  }

  private func refreshStatusIcon() {
    let currentSnapshot = displayController.snapshot()
    let symbolName = currentSnapshot.builtinIsActive ? "laptopcomputer" : "display"
    statusItem.button?.image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: "Mac Monitor Control"
    )
  }

  private func rebuildMenu() {
    statusMenu.removeAllItems()
    let currentSnapshot = displayController.snapshot()

    let builtinStatus: String
    if currentSnapshot.builtinDisplayID == nil {
      builtinStatus = "Built-in Display: Not found"
    } else {
      builtinStatus = "Built-in Display: \(currentSnapshot.builtinIsActive ? "On" : "Off")"
    }

    addInformationalItem(builtinStatus)
    addInformationalItem(currentSnapshot.externalDisplaySummary)

    statusMenu.addItem(.separator())

    let toggleTitle =
      currentSnapshot.builtinIsActive
      ? "Turn Built-in Display Off"
      : "Turn Built-in Display On"
    let toggleItem = NSMenuItem(
      title: toggleTitle,
      action: #selector(toggleBuiltinDisplay),
      keyEquivalent: ""
    )
    toggleItem.target = self
    toggleItem.isEnabled =
      currentSnapshot.builtinIsActive
      ? currentSnapshot.canDisableBuiltinDisplay && displayController.isControlAvailable
        && displayController.isSafetyRestoreActive
      : currentSnapshot.builtinDisplayID != nil && displayController.isControlAvailable
    statusMenu.addItem(toggleItem)

    if currentSnapshot.builtinIsActive,
      let reason = currentSnapshot.disableBlockReason
    {
      addInformationalItem(reason, indented: true)
    } else if !displayController.isControlAvailable {
      addInformationalItem("Display control is unavailable on this macOS version.", indented: true)
    }

    let refreshItem = NSMenuItem(
      title: "Refresh Displays",
      action: #selector(refreshDisplays),
      keyEquivalent: "r"
    )
    refreshItem.target = self
    statusMenu.addItem(refreshItem)

    statusMenu.addItem(.separator())
    addInformationalItem(
      displayController.isSafetyRestoreActive
        ? "Safety restore is active"
        : "Safety restore is unavailable"
    )
    if displayController.lastRecoveryErrorDescription != nil {
      addInformationalItem("Display recovery is retrying automatically", indented: true)
    }

    let quitItem = NSMenuItem(
      title: "Restore Built-in Display and Quit",
      action: #selector(quitApplication),
      keyEquivalent: "q"
    )
    quitItem.target = self
    statusMenu.addItem(quitItem)
  }

  private func addInformationalItem(_ title: String, indented: Bool = false) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    item.indentationLevel = indented ? 1 : 0
    statusMenu.addItem(item)
  }

  private func observeSleepAndWake() {
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(systemWillSleep),
      name: NSWorkspace.willSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(screenDidSleep),
      name: NSWorkspace.screensDidSleepNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(sessionDidResignActive),
      name: NSWorkspace.sessionDidResignActiveNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(systemDidWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(screenDidWake),
      name: NSWorkspace.screensDidWakeNotification,
      object: nil
    )
    workspaceNotificationCenter.addObserver(
      self,
      selector: #selector(sessionDidBecomeActive),
      name: NSWorkspace.sessionDidBecomeActiveNotification,
      object: nil
    )
  }

  private func showError(title: String, error: Error) {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText =
      (error as? LocalizedError)?.errorDescription
      ?? error.localizedDescription
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
