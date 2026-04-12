import AppKit

final class OSDWindow {
  static let shared = OSDWindow()

  private var window: NSWindow?
  private var label: NSTextField?
  private var hideTimer: Timer?

  private init() {}

  func show(message: String) {
    guard UserDefaults.standard.bool(forKey: "showOSD") else { return }

    hideTimer?.invalidate()
    hideTimer = nil

    if window == nil {
      createWindow()
    }

    guard let window = window, let label = label else { return }

    // Adjust font size based on message length
    let fontSize: CGFloat
    switch message.count {
    case 0...2: fontSize = 48
    case 3...6: fontSize = 32
    default: fontSize = 24
    }
    label.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    label.stringValue = message

    // Calculate window size based on text content
    let padding: CGFloat = 24
    let minSize: CGFloat = 140
    let maxWidth: CGFloat = 300
    let minHeight: CGFloat = 140

    // Measure single-line width first (extra 8pt buffer for text field internal margins)
    let singleLineSize = label.attributedStringValue.size()
    let windowWidth = min(max(ceil(singleLineSize.width) + padding * 2 + 8, minSize), maxWidth)

    // Measure wrapped height within the chosen width
    let labelWidth = windowWidth - padding * 2
    let boundingRect = label.attributedStringValue.boundingRect(
      with: NSSize(width: labelWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading])
    let windowHeight = max(boundingRect.height + padding * 2, minHeight)

    window.setContentSize(NSSize(width: windowWidth, height: windowHeight))

    // Position centered on cursor's screen
    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    if let screen = screen {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.midX - windowWidth / 2
      let y = screenFrame.midY - windowHeight / 2
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
    let visualEffect = NSVisualEffectView()
    visualEffect.material = .hudWindow
    visualEffect.state = .active
    visualEffect.wantsLayer = true
    visualEffect.layer?.cornerRadius = 18
    visualEffect.layer?.masksToBounds = true
    visualEffect.autoresizingMask = [.width, .height]
    visualEffect.frame = NSRect(x: 0, y: 0, width: windowSize, height: windowSize)

    let label = NSTextField(wrappingLabelWithString: "")
    label.font = NSFont.systemFont(ofSize: 48, weight: .medium)
    label.textColor = .labelColor
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    label.drawsBackground = false
    label.isBordered = false
    label.isEditable = false
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping

    visualEffect.addSubview(label)
    window.contentView = visualEffect

    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: visualEffect.leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(lessThanOrEqualTo: visualEffect.trailingAnchor, constant: -24),
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
