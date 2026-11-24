import AppKit
import ISS

final class OSDWindow {
  static let shared = OSDWindow()
  private var window: NSWindow?
  private var label: NSTextField?
  private var hideTimer: Timer?
  private var lastSpaceIndex: UInt32?

  // Slide distance and share of the display duration spent fading in/out
  private let slideDistance: CGFloat = 80
  private let fadeInShare = 0.45
  private let fadeOutShare = 0.15

  private init() {}

  // Track space changes made outside the app so the slide direction stays correct
  func noteCurrentSpace(_ index: UInt32) {
    lastSpaceIndex = index
  }

  func show(spaceIndex: UInt32) {
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

    label.stringValue = "\(spaceIndex + 1)"

    // Enter from the side we are switching towards, like the space itself
    var slideOffset: CGFloat = 0
    if let lastSpaceIndex = lastSpaceIndex, lastSpaceIndex != spaceIndex {
      slideOffset = spaceIndex > lastSpaceIndex ? slideDistance : -slideDistance
    }
    lastSpaceIndex = spaceIndex

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

    let durationMs = UserDefaults.standard.object(forKey: "osdDurationMs") as? Int ?? 500
    let duration = Double(durationMs) / 1000.0
    let animated = UserDefaults.standard.bool(forKey: "animateOSD")

    if animated {
      let finalFrame = window.frame
      window.setFrame(finalFrame.offsetBy(dx: slideOffset, dy: 0), display: false)
      window.alphaValue = 0.0
      window.orderFrontRegardless()

      NSAnimationContext.runAnimationGroup({ context in
        context.duration = duration * fadeInShare
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        window.animator().setFrame(finalFrame, display: true)
        window.animator().alphaValue = 1.0
      })
    } else {
      window.alphaValue = 1.0
      window.orderFrontRegardless()
    }

    let fadeOut = animated ? duration * fadeOutShare : 0.2
    hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      self?.hide(over: fadeOut)
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

  private func hide(over duration: TimeInterval) {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = duration
      window?.animator().alphaValue = 0.0
    })
  }
}
