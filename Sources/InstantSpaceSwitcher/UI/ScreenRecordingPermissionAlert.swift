import AppKit

@MainActor
final class ScreenRecordingPermissionAlert: NSObject {
  private static var hasPresented = false
  private static var currentAlert: ScreenRecordingPermissionAlert?

  private let window: NSPanel

  private override init() {
    window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    super.init()

    window.title = "Screen Recording Permission"
    window.level = .floating
    window.isFloatingPanel = true
    window.hidesOnDeactivate = false
    window.isReleasedWhenClosed = false

    let message = NSTextField(wrappingLabelWithString:
      "Instant Space Switcher can’t show the desktop transition because Screen Recording permission is off. Space switching will continue without the animation.")
    message.font = .systemFont(ofSize: NSFont.systemFontSize)

    let openSettingsButton = NSButton(
      title: "Open Screen Recording Settings",
      target: self,
      action: #selector(openScreenRecordingSettings)
    )
    openSettingsButton.bezelStyle = .rounded

    let dismissButton = NSButton(
      title: "Later",
      target: self,
      action: #selector(dismiss)
    )
    dismissButton.bezelStyle = .rounded

    let buttons = NSStackView(views: [dismissButton, openSettingsButton])
    buttons.orientation = .horizontal
    buttons.alignment = .centerY
    buttons.distribution = .equalSpacing

    let content = NSStackView(views: [message, buttons])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 18
    content.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
    window.contentView?.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
      content.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
      content.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
      message.widthAnchor.constraint(equalTo: content.widthAnchor),
      buttons.widthAnchor.constraint(equalTo: content.widthAnchor)
    ])
  }

  static func presentOnce() {
    guard !hasPresented else { return }
    hasPresented = true
    let alert = ScreenRecordingPermissionAlert()
    currentAlert = alert
    alert.window.center()
    alert.window.orderFrontRegardless()
  }

  @objc private func openScreenRecordingSettings() {
    NSWorkspace.shared.open(SpaceTransitionCaptureError.screenRecordingSettingsURL)
    dismiss()
  }

  @objc private func dismiss() {
    window.orderOut(nil)
    Self.currentAlert = nil
  }
}
