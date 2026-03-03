import AppKit
import Carbon

final class ShortcutRecorderControl: NSView {
  private static weak var activeRecorder: ShortcutRecorderControl?

  static func cancelActiveRecording() {
    activeRecorder?.isRecording = false
  }

  var isRecording = false {
    didSet {
      needsDisplay = true
      if isRecording {
        keyPressed = false
        HotKeyManager.shared.unregisterAll()
        startEventTapRecording()
        Self.activeRecorder = self
      } else {
        stopEventTapRecording()
        if Self.activeRecorder === self {
          Self.activeRecorder = nil
        }
      }
    }
  }

  private var keyPressed = false

  var currentShortcut: HotkeyCombination? {
    didSet {
      needsDisplay = true
    }
  }

  var onRecordingComplete: ((HotkeyCombination) -> Void)?
  var onRecordingCancelled: (() -> Void)?

  override var acceptsFirstResponder: Bool { true }
  override var canBecomeKeyView: Bool { true }

  private func startEventTapRecording() {
    GlobalEventTapRecorder.shared.startRecording(
      onKeyPress: { [weak self] event in
        self?.handleKeyEvent(event)
      },
      onMouseClick: { [weak self] in
        print("[ShortcutRecorder] Mouse click detected - cancelling recording")
        self?.isRecording = false
      }
    )
  }

  private func stopEventTapRecording() {
    GlobalEventTapRecorder.shared.stopRecording()
  }

  private func handleKeyEvent(_ event: NSEvent) {
    print(
      "[ShortcutRecorder] Event tap captured - keyCode: \(event.keyCode), modifiers: \(event.modifierFlags)"
    )

    // Ignore additional key presses after first key
    guard !keyPressed else {
      print("[ShortcutRecorder] Already captured a key, ignoring")
      NSSound.beep()
      return
    }

    keyPressed = true

    // Handle escape
    if event.keyCode == UInt16(kVK_Escape) {
      print("[ShortcutRecorder] Escape - cancelling")
      isRecording = false
      onRecordingCancelled?()
      return
    }

    // Try to create combination
    guard let combination = HotkeyCombination.from(event: event), combination.isValid else {
      print("[ShortcutRecorder] Invalid combination")
      NSSound.beep()
      keyPressed = false
      return
    }

    print("[ShortcutRecorder] Valid combination: \(combination.displayString)")
    isRecording = false
    onRecordingComplete?(combination)
    // Hotkeys will be re-registered when store updates
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    // Draw background
    if isRecording {
      NSColor.selectedControlColor.withAlphaComponent(0.3).setFill()
    } else {
      NSColor.controlBackgroundColor.setFill()
    }

    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
    path.fill()

    // Draw border
    NSColor.separatorColor.setStroke()
    path.lineWidth = 1
    path.stroke()

    // Draw text
    let text = isRecording ? "Press keys..." : (currentShortcut?.displayString ?? "Click to record")
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: NSColor.labelColor,
    ]

    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
      x: (bounds.width - textSize.width) / 2,
      y: (bounds.height - textSize.height) / 2,
      width: textSize.width,
      height: textSize.height
    )

    text.draw(in: textRect, withAttributes: attributes)
  }

  override func mouseDown(with event: NSEvent) {
    print("[ShortcutRecorder] mouseDown triggered")

    // Check accessibility permissions before starting recording
    if !AXIsProcessTrusted() {
      print("[ShortcutRecorder] Accessibility permission not granted")
      showAccessibilityAlert()
      return
    }

    // Stop any other active recorder
    if let activeRecorder = Self.activeRecorder, activeRecorder !== self {
      print("[ShortcutRecorder] Stopping other active recorder")
      activeRecorder.isRecording = false
    }

    if !isRecording {
      print("[ShortcutRecorder] Starting recording")
      isRecording = true
    }
  }

  private func showAccessibilityAlert() {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText =
      "\(Constants.appName) needs Accessibility permissions to record keyboard shortcuts.\n\nPlease enable it in System Settings > Privacy & Security > Accessibility."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
