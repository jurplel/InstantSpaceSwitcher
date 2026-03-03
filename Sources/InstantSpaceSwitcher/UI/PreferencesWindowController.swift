import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController {
  private var globalMonitor: Any?

  convenience init() {
    let tabViewController = PreferencesTabViewController()

    let window = KeyWindow(
      contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    window.title = "\(Constants.appName) Settings"
    window.contentViewController = tabViewController
    window.isReleasedWhenClosed = false
    window.center()

    self.init(window: window)
    window.delegate = self
  }

  func present() {
    // Check accessibility permissions
    if !AXIsProcessTrusted() {
      showAccessibilityAlert()
    }

    guard let window = window else { return }

    // Ensure window comes to front
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()

    NSApp.activate(ignoringOtherApps: true)

    // Restore normal level after a brief moment
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.window?.level = .normal
      self?.startEventMonitor()
    }
  }

  private func startEventMonitor() {
    stopEventMonitor()

    // Only use global monitor - check manually if our window should handle the event
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self, let window = self.window else { return }

      // Only handle if our window is visible and on the active space
      guard window.isVisible && window.isOnActiveSpace else { return }

      // Only handle command key shortcuts
      guard event.modifierFlags.contains(.command) else { return }

      // Check if our window is actually the frontmost window system-wide
      guard self.isWindowFrontmost(window) else { return }

      switch event.charactersIgnoringModifiers {
      case "w":
        DispatchQueue.main.async {
          window.performClose(nil)
        }
      case "q":
        DispatchQueue.main.async {
          NSApp.terminate(nil)
        }
      default:
        break
      }
    }
  }

  private func isWindowFrontmost(_ window: NSWindow) -> Bool {
    let windowNumber = CGWindowID(window.windowNumber)

    // Get list of all windows on screen, ordered front to back
    guard
      let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else {
      return false
    }

    // Find the first window that's not a menu bar or dock
    for windowInfo in windowList {
      guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
        layer == 0
      else { continue }  // Layer 0 is normal windows

      guard let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else { continue }

      // This is the frontmost normal window
      return windowID == windowNumber
    }

    return false
  }

  private func stopEventMonitor() {
    if let monitor = globalMonitor {
      NSEvent.removeMonitor(monitor)
      globalMonitor = nil
    }
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

  func windowWillClose(_ notification: Notification) {
    stopEventMonitor()
  }
}
