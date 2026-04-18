import AppKit
import ISS
import ServiceManagement

final class GeneralSettingsViewController: NSViewController {
  private let showOSDCheckbox = NSButton(
    checkboxWithTitle: "Show on-screen display when switching spaces", target: nil, action: nil)
  private let osdDurationPopup = NSPopUpButton()
  private let osdDurationLabel = NSTextField(labelWithString: "Duration:")
  private let overlayDetectionCheckbox = NSButton(
    checkboxWithTitle: "Enable Mission Control/Exposé detection (experimental)", target: nil, action: nil)
  private let showOSDInMissionControlCheckbox = NSButton(
    checkboxWithTitle: "Show on-screen display in Mission Control", target: nil, action: nil)
  private let swipeOverrideCheckbox = NSButton(
    checkboxWithTitle: "Override swipe gesture", target: nil, action: nil)
  private let animationSpeedPopup = NSPopUpButton()
  private let animationSpeedLabel = NSTextField(labelWithString: "Animation Speed:")
  private let launchAtLoginCheckbox = NSButton(
    checkboxWithTitle: "Launch at login", target: nil, action: nil)

  private let durationPresets = [100, 200, 300, 500, 750, 1000]
  private let animationSpeedOptions = ["Normal", "Fast", "Faster", "Fastest", "Instant"]
  private let animationSpeedValues: [Double] = [40.0, 50.0, 60.0, 80.0, 2000.0]

  private let defaults = UserDefaults.standard

  override func loadView() {
    self.view = FormView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupUI()
    loadSettings()
  }

  private func setupUI() {
    guard let formView = view as? FormView else { return }

    if formView.hasRows { return }

    // Targets/Actions
    showOSDCheckbox.target = self
    showOSDCheckbox.action = #selector(showOSDChanged)
    osdDurationPopup.target = self
    osdDurationPopup.action = #selector(osdDurationChanged)
    overlayDetectionCheckbox.target = self
    overlayDetectionCheckbox.action = #selector(overlayDetectionChanged)
    showOSDInMissionControlCheckbox.target = self
    showOSDInMissionControlCheckbox.action = #selector(showOSDInMissionControlChanged)
    swipeOverrideCheckbox.target = self
    swipeOverrideCheckbox.action = #selector(swipeOverrideChanged)
    animationSpeedPopup.target = self
    animationSpeedPopup.action = #selector(animationSpeedChanged)
    launchAtLoginCheckbox.target = self
    launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

    // Populate data
    for duration in durationPresets { osdDurationPopup.addItem(withTitle: "\(duration)ms") }
    for speed in animationSpeedOptions { animationSpeedPopup.addItem(withTitle: speed) }

    // System
    let systemLabel = NSTextField(labelWithString: "System:")
    formView.addRow(label: systemLabel, control: launchAtLoginCheckbox)
    formView.addRow(label: nil, control: swipeOverrideCheckbox)

    let experimentalTitle = NSMutableAttributedString(string: "Enable Mission Control/Exposé detection\n")
    let sublabel = NSAttributedString(
      string: "Experimental—may be flaky",
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor
      ])
    experimentalTitle.append(sublabel)
    overlayDetectionCheckbox.attributedTitle = experimentalTitle
    
    formView.addRow(label: nil, control: overlayDetectionCheckbox)
    formView.addSectionSpacing()

    // Animation Speed
    let animationLabel = NSTextField(labelWithString: "Animation Speed:")
    formView.addRow(label: animationLabel, control: animationSpeedPopup)
    formView.addSectionSpacing()

    // OSD
    let osdLabel = NSTextField(labelWithString: "On-Screen Display:")
    showOSDCheckbox.title = "Show for"
    showOSDInMissionControlCheckbox.title = "Show in Mission Control"
    
    let osdContainer = NSStackView()
    osdContainer.orientation = .horizontal
    osdContainer.spacing = 8
    osdContainer.addArrangedSubview(showOSDCheckbox)
    osdContainer.addArrangedSubview(osdDurationPopup)
    osdContainer.addArrangedSubview(NSTextField(labelWithString: "when switching spaces"))
    
    formView.addRow(label: osdLabel, control: osdContainer)
    formView.addRow(label: nil, control: showOSDInMissionControlCheckbox)
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
    overlayDetectionCheckbox.state = defaults.object(forKey: "overlayDetectionEnabled") as? Bool ?? true ? .on : .off
    let overlayDetectionEnabled = overlayDetectionCheckbox.state == .on
    showOSDInMissionControlCheckbox.isEnabled = showOSD && overlayDetectionEnabled
    showOSDInMissionControlCheckbox.state = defaults.bool(forKey: "showOSDInMissionControl") ? .on : .off

    swipeOverrideCheckbox.state = defaults.bool(forKey: "swipeOverride") ? .on : .off

    let animationSpeedValue = defaults.double(forKey: "gestureSpeed")
    if animationSpeedValue > 0 {
      if let index = animationSpeedValues.firstIndex(where: { $0 == animationSpeedValue }) {
        animationSpeedPopup.selectItem(at: index)
      } else {
        animationSpeedPopup.selectItem(at: 4)
      }
    } else {
      animationSpeedPopup.selectItem(at: 4)
    }

    launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  @objc private func showOSDChanged(_ sender: NSButton) {
    let isEnabled = sender.state == .on
    defaults.set(isEnabled, forKey: "showOSD")
    osdDurationPopup.isEnabled = isEnabled
    let overlayDetectionEnabled = overlayDetectionCheckbox.state == .on
    showOSDInMissionControlCheckbox.isEnabled = isEnabled && overlayDetectionEnabled
  }

  @objc private func overlayDetectionChanged(_ sender: NSButton) {
    let isEnabled = sender.state == .on
    defaults.set(isEnabled, forKey: "overlayDetectionEnabled")
    let showOSDEnabled = showOSDCheckbox.state == .on
    showOSDInMissionControlCheckbox.isEnabled = showOSDEnabled && isEnabled
    iss_set_overlay_detection_enabled(isEnabled)
  }

  @objc private func showOSDInMissionControlChanged(_ sender: NSButton) {
    defaults.set(sender.state == .on, forKey: "showOSDInMissionControl")
  }

  @objc private func osdDurationChanged(_ sender: NSPopUpButton) {
    let index = sender.indexOfSelectedItem
    guard index >= 0 && index < durationPresets.count else { return }
    let duration = durationPresets[index]
    defaults.set(duration, forKey: "osdDurationMs")
  }

  @objc private func swipeOverrideChanged(_ sender: NSButton) {
    let isEnabled = sender.state == .on
    defaults.set(isEnabled, forKey: "swipeOverride")
    iss_set_swipe_override(isEnabled)
  }

  @objc private func animationSpeedChanged(_ sender: NSPopUpButton) {
    let index = sender.indexOfSelectedItem
    guard index >= 0 && index < animationSpeedOptions.count else { return }

    var velocity: Double
    if index < animationSpeedValues.count {
      velocity = animationSpeedValues[index]
    } else {
      velocity = 2000.0
    }

    defaults.set(velocity, forKey: "gestureSpeed")
    iss_set_gesture_speed(velocity)
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
