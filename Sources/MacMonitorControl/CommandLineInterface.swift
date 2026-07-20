import Foundation

enum CommandLineInterface {
  static func runIfRequested(arguments: [String]) -> Int32? {
    guard arguments.count > 1 else { return nil }

    let controller = CoreGraphicsDisplayController()

    switch arguments[1] {
    case "--status":
      let snapshot = controller.snapshot()
      let builtinStatus: String
      if snapshot.builtinDisplayID == nil {
        builtinStatus = "not found"
      } else {
        builtinStatus = snapshot.builtinIsActive ? "on" : "off"
      }

      print("Built-in display: \(builtinStatus)")
      print("\(snapshot.externalDisplaySummary)")
      print("Display control available: \(controller.isControlAvailable ? "yes" : "no")")
      return 0

    case "--on":
      do {
        try controller.setBuiltinDisplayEnabled(true)
        print("Built-in display is on.")
        return 0
      } catch {
        writeError(error.localizedDescription)
        return 1
      }

    case "--self-test":
      return runSelfTests()

    case "--help", "-h":
      printHelp()
      return 0

    default:
      writeError("Unknown option: \(arguments[1])")
      printHelp()
      return 2
    }
  }

  private static func printHelp() {
    print(
      """
      Usage: MacMonitorControl [option]

        --status  Print the current display state.
        --on      Turn the built-in display on (recovery command).
        --self-test
                  Run hardware-independent safety policy checks.
        --help    Show this help.

      Run without an option to open the menu-bar app.
      Turning the display off is intentionally available only through the app,
      where automatic safety recovery remains active.
      """)
  }

  private static func runSelfTests() -> Int32 {
    let cases: [(String, Bool)] = [
      (
        "allows disable with an active external display",
        DisplaySnapshot(
          builtinDisplayID: 1,
          builtinIsActive: true,
          activeExternalDisplayCount: 1
        ).canDisableBuiltinDisplay
      ),
      (
        "blocks disable without an external display",
        !DisplaySnapshot(
          builtinDisplayID: 1,
          builtinIsActive: true,
          activeExternalDisplayCount: 0
        ).canDisableBuiltinDisplay
      ),
      (
        "blocks disable without a built-in display",
        !DisplaySnapshot(
          builtinDisplayID: nil,
          builtinIsActive: false,
          activeExternalDisplayCount: 2
        ).canDisableBuiltinDisplay
      ),
      (
        "reports the external display count",
        DisplaySnapshot(
          builtinDisplayID: 1,
          builtinIsActive: true,
          activeExternalDisplayCount: 2
        ).externalDisplaySummary == "2 active external displays"
      ),
      (
        "restores an inactive built-in display after the last external disconnects",
        DisplaySnapshot(
          builtinDisplayID: 1,
          builtinIsActive: false,
          activeExternalDisplayCount: 0
        ).requiresSafetyRestore
      ),
      (
        "keeps the built-in display off while an external display remains",
        !DisplaySnapshot(
          builtinDisplayID: 1,
          builtinIsActive: false,
          activeExternalDisplayCount: 1
        ).requiresSafetyRestore
      ),
    ]

    var failed = false
    for (name, passed) in cases {
      print("\(passed ? "PASS" : "FAIL")  \(name)")
      failed = failed || !passed
    }

    return failed ? 1 : 0
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("MacMonitorControl: \(message)\n".utf8))
  }
}
