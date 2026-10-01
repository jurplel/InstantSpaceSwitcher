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
  private let launchAtLoginCheckbox = NSButton(
    checkboxWithTitle: "Launch at login", target: nil, action: nil)
  private let appSwitchOverrideCheckbox = NSButton(
    checkboxWithTitle: "Use animation settings when switching apps", target: nil, action: nil)
  private let hideMenuBarIconCheckbox = NSButton(
    checkboxWithTitle: "Hide menu bar icon", target: nil, action: nil)

  private let durationPresets = [100, 200, 300, 500, 750, 1000]

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
    appSwitchOverrideCheckbox.target = self
    appSwitchOverrideCheckbox.action = #selector(appSwitchOverrideChanged)
    launchAtLoginCheckbox.target = self
    launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
    hideMenuBarIconCheckbox.target = self
    hideMenuBarIconCheckbox.action = #selector(hideMenuBarIconChanged)

    // Populate data
    for duration in durationPresets { osdDurationPopup.addItem(withTitle: "\(duration)ms") }

    // System
    let systemLabel = NSTextField(labelWithString: "System:")
    formView.addRow(label: systemLabel, control: launchAtLoginCheckbox)
    formView.addRow(label: nil, control: hideMenuBarIconCheckbox)
    formView.addRow(label: nil, control: swipeOverrideCheckbox)
    formView.addRow(label: nil, control: appSwitchOverrideCheckbox)
    appSwitchOverrideCheckbox.toolTip = "Keeps the native Command-Tab chooser. Also applies when activating an app from the Dock."

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

    hideMenuBarIconCheckbox.state = defaults.bool(forKey: "hideMenuBarIcon") ? .on : .off
    swipeOverrideCheckbox.state = defaults.bool(forKey: "swipeOverride") ? .on : .off
    appSwitchOverrideCheckbox.state = (defaults.object(forKey: "appSwitchOverride") as? Bool ?? true) ? .on : .off

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

  @objc private func appSwitchOverrideChanged(_ sender: NSButton) {
    let enabled = sender.state == .on
    defaults.set(enabled, forKey: "appSwitchOverride")
    (NSApp.delegate as? AppDelegate)?.setAppSwitchOverrideEnabled(enabled)
  }

  @objc private func hideMenuBarIconChanged(_ sender: NSButton) {
    let hide = sender.state == .on
    defaults.set(hide, forKey: "hideMenuBarIcon")
    (NSApp.delegate as? AppDelegate)?.setMenuBarIconVisible(!hide)
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
