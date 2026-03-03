import AppKit
import ServiceManagement

final class GeneralSettingsViewController: NSViewController {
  private let showOSDCheckbox = NSButton(
    checkboxWithTitle: "Show on-screen display when switching spaces", target: nil, action: nil)
  private let osdDurationPopup = NSPopUpButton()
  private let osdDurationLabel = NSTextField(labelWithString: "Duration:")
  private let launchAtLoginCheckbox = NSButton(
    checkboxWithTitle: "Launch at login", target: nil, action: nil)

  private let durationPresets = [100, 200, 300, 500, 750, 1000]

  private let defaults = UserDefaults.standard

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
    loadSettings()
  }

  private func setupUI() {
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.alignment = .leading
    stackView.spacing = 16
    stackView.translatesAutoresizingMaskIntoConstraints = false

    let generalLabel = NSTextField(labelWithString: "General Settings")
    generalLabel.font = NSFont.boldSystemFont(ofSize: 13)

    showOSDCheckbox.target = self
    showOSDCheckbox.action = #selector(showOSDChanged)

    for duration in durationPresets {
      osdDurationPopup.addItem(withTitle: "\(duration)ms")
    }
    osdDurationPopup.target = self
    osdDurationPopup.action = #selector(osdDurationChanged)

    let osdDurationContainer = NSStackView()
    osdDurationContainer.orientation = .horizontal
    osdDurationContainer.spacing = 8
    osdDurationContainer.addArrangedSubview(osdDurationLabel)
    osdDurationContainer.addArrangedSubview(osdDurationPopup)

    launchAtLoginCheckbox.target = self
    launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

    stackView.addArrangedSubview(generalLabel)
    stackView.addArrangedSubview(showOSDCheckbox)
    stackView.addArrangedSubview(osdDurationContainer)
    stackView.addArrangedSubview(launchAtLoginCheckbox)

    view.addSubview(stackView)

    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      stackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
    ])
  }

  private func loadSettings() {
    let showOSD = defaults.bool(forKey: "showOSD")
    showOSDCheckbox.state = showOSD ? .on : .off

    let durationMs = defaults.object(forKey: "osdDurationMs") as? Int ?? 200
    if let index = durationPresets.firstIndex(of: durationMs) {
      osdDurationPopup.selectItem(at: index)
    } else {
      osdDurationPopup.selectItem(at: 1)
    }

    osdDurationPopup.isEnabled = showOSD

    launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  @objc private func showOSDChanged(_ sender: NSButton) {
    let isEnabled = sender.state == .on
    defaults.set(isEnabled, forKey: "showOSD")
    osdDurationPopup.isEnabled = isEnabled
  }

  @objc private func osdDurationChanged(_ sender: NSPopUpButton) {
    let index = sender.indexOfSelectedItem
    guard index >= 0 && index < durationPresets.count else { return }
    let duration = durationPresets[index]
    defaults.set(duration, forKey: "osdDurationMs")
  }

  @objc private func launchAtLoginChanged(_ sender: NSButton) {
    let shouldEnable = sender.state == .on

    do {
      if shouldEnable {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      NSSound.beep()
      sender.state = shouldEnable ? .off : .on

      let alert = NSAlert()
      alert.messageText = "Failed to \(shouldEnable ? "enable" : "disable") launch at login"
      alert.informativeText = error.localizedDescription
      alert.alertStyle = .warning
      alert.runModal()
    }
  }
}
