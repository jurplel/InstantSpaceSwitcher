import AppKit

final class KeyWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.modifierFlags.contains(.command) else {
      return super.performKeyEquivalent(with: event)
    }

    switch event.charactersIgnoringModifiers {
    case "w":
      performClose(nil)
      return true
    case "q":
      NSApp.terminate(nil)
      return true
    default:
      return super.performKeyEquivalent(with: event)
    }
  }
}
