import AppKit
import ISS

final class OSDWindow {
  static let shared = OSDWindow()
  private var window: NSWindow?
  private var label: NSTextField?
  private var hideTimer: Timer?

  private init() {}

  func show(message: String) {
    guard UserDefaults.standard.bool(forKey: "showOSD") else { return }
    // Mission Control OSD suppression requires overlay detection enabled
    let overlayDetectionEnabled = UserDefaults.standard.bool(forKey: "overlayDetectionEnabled")
    if overlayDetectionEnabled && iss_is_mission_control_active() && !UserDefaults.standard.bool(forKey: "showOSDInMissionControl") {
      return
    }

    hideTimer?.invalidate()
    hideTimer = nil

    if window == nil {
      createWindow()
    }

    guard let window = window, let label = label else { return }

    label.stringValue = message

    // Position on cursor's screen
    let windowSize: CGFloat = 140
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    if let screen = screen {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.midX - windowSize / 2
      let y = screenFrame.midY - windowSize / 2
      window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    window.alphaValue = 1.0
    window.orderFrontRegardless()

    let durationMs = UserDefaults.standard.object(forKey: "osdDurationMs") as? Int ?? 500
    let duration = Double(durationMs) / 1000.0
    hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      self?.hide()
    }
  }

  private func createWindow() {
    let windowSize: CGFloat = 140

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: windowSize, height: windowSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false

    // Use vibrancy for native macOS look
    let visualEffect = NSVisualEffectView(
      frame: NSRect(x: 0, y: 0, width: windowSize, height: windowSize))
    visualEffect.material = .hudWindow
    visualEffect.state = .active
    visualEffect.wantsLayer = true
    visualEffect.layer?.cornerRadius = 18
    visualEffect.layer?.masksToBounds = true

    let label = NSTextField(labelWithString: "")
    label.font = NSFont.systemFont(ofSize: 48, weight: .medium)
    label.textColor = .labelColor
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    label.drawsBackground = false
    label.isBordered = false
    label.isEditable = false

    visualEffect.addSubview(label)
    window.contentView = visualEffect

    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
    ])

    self.window = window
    self.label = label
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.2
      window?.animator().alphaValue = 0.0
    })
  }
}
