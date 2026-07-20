import CoreGraphics

struct DisplaySnapshot: Equatable {
  let builtinDisplayID: CGDirectDisplayID?
  let builtinIsActive: Bool
  let activeExternalDisplayCount: Int

  var canDisableBuiltinDisplay: Bool {
    builtinDisplayID != nil && builtinIsActive && activeExternalDisplayCount > 0
  }

  var requiresSafetyRestore: Bool {
    builtinDisplayID != nil && !builtinIsActive && activeExternalDisplayCount == 0
  }

  var disableBlockReason: String? {
    guard builtinDisplayID != nil else {
      return "No built-in display was found."
    }

    guard builtinIsActive else {
      return "The built-in display is already off."
    }

    guard activeExternalDisplayCount > 0 else {
      return "Connect and activate an external display first."
    }

    return nil
  }

  var externalDisplaySummary: String {
    switch activeExternalDisplayCount {
    case 0:
      return "No active external displays"
    case 1:
      return "1 active external display"
    default:
      return "\(activeExternalDisplayCount) active external displays"
    }
  }
}
