import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
  convenience init() {
    let tabViewController = PreferencesTabViewController()

    let panel = PreferencesPanel(
      contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.title = "\(Constants.appName) Settings"
    panel.contentViewController = tabViewController
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.center()

    self.init(window: panel)
    panel.delegate = self
  }

  func present() {
    // Check accessibility permissions
    if !AXIsProcessTrusted() {
      showAccessibilityAlert()
    }

    guard let window = window else { return }

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func showAccessibilityAlert() {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText =
      "\(Constants.appName) needs Accessibility permissions to record keyboard shortcuts and switch spaces.\n\nPlease enable it in System Settings > Privacy & Security > Accessibility."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      // Open System Settings to Privacy & Security > Accessibility
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }
}

extension PreferencesWindowController: NSWindowDelegate {
  func windowDidResignKey(_ notification: Notification) {
    // Cancel any active recording when window loses focus
    ShortcutRecorderControl.cancelActiveRecording()
  }
}
