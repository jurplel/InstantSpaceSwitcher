import AppKit
import ISS

@MainActor
final class OSDWindow {
  static let shared = OSDWindow()
  private var window: NSWindow?
  private var contentView: OSDContentView?
  private var hideTimer: Timer?

  private init() {}

  func show(message: String, screenID: UInt32) {
    guard UserDefaults.standard.bool(forKey: "showOSD") else { return }
    // Mission Control OSD suppression requires overlay detection enabled
    let overlayDetectionEnabled = UserDefaults.standard.bool(forKey: "overlayDetectionEnabled")
    if overlayDetectionEnabled && iss_is_mission_control_active() && !UserDefaults.standard.bool(forKey: "showOSDInMissionControl") {
      return
    }

    let screen = screenID == 0 ? NSScreen.main : NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == screenID
    }
    guard let screen else { return }

    hideTimer?.invalidate()
    hideTimer = nil

    if window == nil {
      createWindow()
    }

    guard let window, let contentView else { return }
    let screenFrame = screen.visibleFrame
    let size = contentView.update(message: message, maximumSize: screenFrame.insetBy(dx: 40, dy: 40).size)
    window.setFrame(NSRect(
      x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2,
      width: size.width, height: size.height), display: true)

    window.alphaValue = 1.0
    window.orderFrontRegardless()

    let durationMs = UserDefaults.standard.object(forKey: "osdDurationMs") as? Int ?? 500
    let duration = Double(durationMs) / 1000.0
    hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.hide() }
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

    let contentView = OSDContentView(frame: window.contentLayoutRect)
    window.contentView = contentView
    self.window = window
    self.contentView = contentView
  }

  private func hide() {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.2
      window?.animator().alphaValue = 0.0
    })
  }
}

final class OSDContentView: NSVisualEffectView {
  let messageLabel = NSTextField(wrappingLabelWithString: "")
  private let padding: CGFloat = 24

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    material = .hudWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 18
    layer?.masksToBounds = true

    messageLabel.textColor = .labelColor
    messageLabel.alignment = .center
    messageLabel.maximumNumberOfLines = 0
    messageLabel.lineBreakMode = .byWordWrapping
    messageLabel.cell?.isScrollable = false
    addSubview(messageLabel)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func update(message: String, maximumSize: NSSize) -> NSSize {
    messageLabel.stringValue = message
    messageLabel.font = .systemFont(ofSize: message.count > 3 ? 36 : 48, weight: .medium)
    let maximumWidth = max(2 * padding + 1, maximumSize.width)
    let maximumHeight = max(2 * padding + 1, maximumSize.height)
    let naturalWidth = messageLabel.cell!.cellSize.width
    var width = min(680, maximumWidth, max(140, ceil(naturalWidth) + 2 * padding))
    var textHeight = measuredTextHeight(width: width)

    if textHeight + 2 * padding > maximumHeight {
      width = maximumWidth
      textHeight = measuredTextHeight(width: width)
    }
    if textHeight + 2 * padding > maximumHeight {
      // Very long names use smaller type so every line stays on screen.
      var lower: CGFloat = 1
      var upper = messageLabel.font!.pointSize
      for _ in 0..<10 {
        let candidate = (lower + upper) / 2
        messageLabel.font = .systemFont(ofSize: candidate, weight: .medium)
        if measuredTextHeight(width: width) + 2 * padding <= maximumHeight {
          lower = candidate
        } else {
          upper = candidate
        }
      }
      messageLabel.font = .systemFont(ofSize: lower, weight: .medium)
      textHeight = measuredTextHeight(width: width)
    }

    let size = NSSize(width: width, height: max(min(140, maximumHeight), textHeight + 2 * padding))
    frame.size = size
    messageLabel.frame = NSRect(
      x: padding, y: (size.height - textHeight) / 2,
      width: size.width - 2 * padding, height: textHeight)
    return size
  }

  private func measuredTextHeight(width: CGFloat) -> CGFloat {
    let bounds = NSRect(x: 0, y: 0, width: width - 2 * padding, height: .greatestFiniteMagnitude)
    return ceil(messageLabel.cell!.cellSize(forBounds: bounds).height)
  }
}
