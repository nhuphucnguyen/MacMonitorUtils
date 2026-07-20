import AppKit
import Darwin

if let exitCode = CommandLineInterface.runIfRequested(arguments: CommandLine.arguments) {
  exit(exitCode)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = appDelegate
application.run()
