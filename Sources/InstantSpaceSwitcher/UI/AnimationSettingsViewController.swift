import AppKit

final class AnimationSettingsViewController: NSViewController {
  private var settings = AnimationSettings.load()
  private let speedPopup = NSPopUpButton()
  private let curvePopup = NSPopUpButton()
  private let durationSlider = NSSlider(value: 220, minValue: 80, maxValue: 1000, target: nil, action: nil)
  private let startSlider = NSSlider(value: 10, minValue: 0, maxValue: 50, target: nil, action: nil)
  private let endSlider = NSSlider(value: 10, minValue: 0, maxValue: 50, target: nil, action: nil)
  private let durationValue = NSTextField(labelWithString: "220 ms")
  private let startValue = NSTextField(labelWithString: "10%")
  private let endValue = NSTextField(labelWithString: "10%")
  private let preview = AnimationCurvePreview()

  override func loadView() { view = FormView() }

  override func viewDidLoad() {
    super.viewDidLoad()
    guard let form = view as? FormView else { return }
    speedPopup.addItems(withTitles: AnimationSettings.speedNames)
    speedPopup.target = self
    speedPopup.action = #selector(speedChanged)
    curvePopup.addItems(withTitles: AnimationSettings.curveNames)
    curvePopup.autoenablesItems = false
    curvePopup.lastItem?.isEnabled = false // Sliders create a custom curve.
    curvePopup.target = self
    curvePopup.action = #selector(curveChanged)
    for (slider, action, label) in [
      (durationSlider, #selector(durationChanged), "Slide duration"),
      (startSlider, #selector(easingChanged), "Ease in"),
      (endSlider, #selector(easingChanged), "Ease out")
    ] {
      slider.target = self
      slider.action = action
      slider.isContinuous = true
      slider.setAccessibilityLabel(label)
    }
    startSlider.toolTip = "Time spent accelerating. 0% starts at full speed; 50% accelerates for half the slide."
    endSlider.toolTip = "Time spent slowing down. Keep this low for a crisp finish."
    form.addRow(label: NSTextField(labelWithString: "Speed:"), control: speedPopup)
    form.addRow(label: NSTextField(labelWithString: "Duration:"), control: sliderRow(durationSlider, durationValue))
    form.addRow(label: NSTextField(labelWithString: "Curve:"), control: curvePopup)
    form.addRow(label: NSTextField(labelWithString: "Ease in:"), control: sliderRow(startSlider, startValue))
    form.addRow(label: NSTextField(labelWithString: "Ease out:"), control: sliderRow(endSlider, endValue))
    form.addRow(label: nil, control: preview)

    updateControls()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    settings = .load()
    updateControls()
  }

  private func sliderRow(_ slider: NSSlider, _ value: NSTextField) -> NSView {
    slider.widthAnchor.constraint(equalToConstant: 304).isActive = true
    value.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    value.alignment = .right
    value.widthAnchor.constraint(equalToConstant: 66).isActive = true
    let row = NSStackView(views: [slider, value])
    row.spacing = 10
    return row
  }

  private func updateControls() {
    speedPopup.selectItem(at: settings.speedIndex)
    curvePopup.selectItem(at: settings.curveIndex)
    durationSlider.doubleValue = settings.duration * 1000
    startSlider.doubleValue = settings.easeIn * 100
    endSlider.doubleValue = settings.easeOut * 100
    durationValue.stringValue = settings.isInstant ? "0 ms" : "\(Int((settings.duration * 1000).rounded())) ms"
    startValue.stringValue = "\(Int((settings.easeIn * 100).rounded()))%"
    endValue.stringValue = "\(Int((settings.easeOut * 100).rounded()))%"
    for control in [durationSlider, startSlider, endSlider, curvePopup] as [NSControl] {
      control.isEnabled = !settings.isInstant
    }
    preview.settings = settings
  }

  private func changed() {
    settings.save()
    updateControls()

  }

  @objc private func speedChanged() {
    let index = speedPopup.indexOfSelectedItem
    if index == 5 {
      settings.customDuration = settings.isInstant ? 0.22 : settings.duration
      settings.speed = 50
    } else if AnimationSettings.speeds.indices.contains(index) {
      settings.speed = AnimationSettings.speeds[index]
      settings.customDuration = 0
    }
    changed()
  }

  @objc private func durationChanged() {
    settings.customDuration = (durationSlider.doubleValue / 10).rounded() / 100
    changed()
  }

  @objc private func curveChanged() {
    let index = curvePopup.indexOfSelectedItem
    if AnimationSettings.curves.indices.contains(index) {
      (settings.easeIn, settings.easeOut) = AnimationSettings.curves[index]
    }
    changed()
  }

  @objc private func easingChanged() {
    settings.easeIn = startSlider.doubleValue.rounded() / 100
    settings.easeOut = endSlider.doubleValue.rounded() / 100
    changed()
  }

}
