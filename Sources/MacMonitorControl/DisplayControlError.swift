import CoreGraphics
import Foundation

enum DisplayControlError: LocalizedError {
  case noBuiltinDisplay
  case noExternalDisplay
  case privateAPINotAvailable
  case beginConfiguration(CGError)
  case configureDisplay(Int32)
  case completeConfiguration(CGError)

  var errorDescription: String? {
    switch self {
    case .noBuiltinDisplay:
      return "No built-in display was found."
    case .noExternalDisplay:
      return "Connect and activate an external display before turning off the built-in display."
    case .privateAPINotAvailable:
      return
        "This macOS version does not expose the display-control function used by Mac Monitor Control."
    case .beginConfiguration(let error):
      return "macOS could not begin a display configuration (error \(error.rawValue))."
    case .configureDisplay(let code):
      return "macOS rejected the display change (error \(code))."
    case .completeConfiguration(let error):
      return "macOS could not apply the display configuration (error \(error.rawValue))."
    }
  }
}
