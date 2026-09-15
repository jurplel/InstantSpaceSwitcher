import AppKit
import Combine

@MainActor
final class HotkeyPreferencesView: NSView {
  private let store: HotkeyStore
  private var recordingIdentifier: HotkeyIdentifier?
  private var cancellables = Set<AnyCancellable>()

  private let titleLabel = NSTextField(labelWithString: "Shortcuts")
  private let leftTitleLabel = NSTextField(labelWithString: "Switch Left")
  private let rightTitleLabel = NSTextField(labelWithString: "Switch Right")
  private let leftShortcutLabel = NSTextField(labelWithString: "")
  private let rightShortcutLabel = NSTextField(labelWithString: "")
  private let leftChangeButton = NSButton(title: "Change…", target: nil, action: nil)
  private let leftResetButton = NSButton(title: "Reset", target: nil, action: nil)
  private let rightChangeButton = NSButton(title: "Change…", target: nil, action: nil)
  private let rightResetButton = NSButton(title: "Reset", target: nil, action: nil)
  private let leftHintLabel = NSTextField(
    labelWithString: "Press the desired key combination. Press Esc to cancel.")
  private let rightHintLabel = NSTextField(
    labelWithString: "Press the desired key combination. Press Esc to cancel.")
  private let restoreDefaultsButton = NSButton(title: "Restore Defaults", target: nil, action: nil)
  private let statusLabel = NSTextField(labelWithString: "")

  init(store: HotkeyStore = .shared) {
    self.store = store
    super.init(frame: .zero)
    setupViews()
    setupConstraints()
    bindStore()
    updateUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupViews() {
    titleLabel.font = .systemFont(ofSize: 16, weight: .bold)

    leftTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    rightTitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

    leftShortcutLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    rightShortcutLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

    leftHintLabel.font = .systemFont(ofSize: 11)
    leftHintLabel.textColor = .secondaryLabelColor
    leftHintLabel.isHidden = true

    rightHintLabel.font = .systemFont(ofSize: 11)
    rightHintLabel.textColor = .secondaryLabelColor
    rightHintLabel.isHidden = true

    leftChangeButton.target = self
    leftChangeButton.action = #selector(leftChangeClicked)
    leftChangeButton.bezelStyle = .rounded
    leftChangeButton.controlSize = .small

    leftResetButton.target = self
    leftResetButton.action = #selector(leftResetClicked)
    leftResetButton.bezelStyle = .rounded
    leftResetButton.controlSize = .small

    rightChangeButton.target = self
    rightChangeButton.action = #selector(rightChangeClicked)
    rightChangeButton.bezelStyle = .rounded
    rightChangeButton.controlSize = .small

    rightResetButton.target = self
    rightResetButton.action = #selector(rightResetClicked)
    rightResetButton.bezelStyle = .rounded
    rightResetButton.controlSize = .small

    restoreDefaultsButton.target = self
    restoreDefaultsButton.action = #selector(restoreDefaultsClicked)
    restoreDefaultsButton.bezelStyle = .rounded

    statusLabel.font = .systemFont(ofSize: 12)
    statusLabel.textColor = .secondaryLabelColor
    statusLabel.alignment = .right
    statusLabel.stringValue = ""

    addSubview(titleLabel)
    addSubview(leftTitleLabel)
    addSubview(leftShortcutLabel)
    addSubview(leftChangeButton)
    addSubview(leftResetButton)
    addSubview(leftHintLabel)
    addSubview(rightTitleLabel)
    addSubview(rightShortcutLabel)
    addSubview(rightChangeButton)
    addSubview(rightResetButton)
    addSubview(rightHintLabel)
    addSubview(restoreDefaultsButton)
    addSubview(statusLabel)
  }

  private func setupConstraints() {
    let views = [
      titleLabel, leftTitleLabel, leftShortcutLabel, leftChangeButton, leftResetButton,
      leftHintLabel,
      rightTitleLabel, rightShortcutLabel, rightChangeButton, rightResetButton, rightHintLabel,
      restoreDefaultsButton, statusLabel,
    ]
    views.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

      leftTitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
      leftTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

      leftShortcutLabel.topAnchor.constraint(equalTo: leftTitleLabel.bottomAnchor, constant: 8),
      leftShortcutLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

      leftResetButton.centerYAnchor.constraint(equalTo: leftShortcutLabel.centerYAnchor),
      leftResetButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      leftResetButton.widthAnchor.constraint(equalToConstant: 60),

      leftChangeButton.centerYAnchor.constraint(equalTo: leftShortcutLabel.centerYAnchor),
      leftChangeButton.trailingAnchor.constraint(
        equalTo: leftResetButton.leadingAnchor, constant: -8),
      leftChangeButton.widthAnchor.constraint(equalToConstant: 100),

      leftHintLabel.topAnchor.constraint(equalTo: leftShortcutLabel.bottomAnchor, constant: 4),
      leftHintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      leftHintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

      rightTitleLabel.topAnchor.constraint(equalTo: leftHintLabel.bottomAnchor, constant: 16),
      rightTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

      rightShortcutLabel.topAnchor.constraint(equalTo: rightTitleLabel.bottomAnchor, constant: 8),
      rightShortcutLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

      rightResetButton.centerYAnchor.constraint(equalTo: rightShortcutLabel.centerYAnchor),
      rightResetButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      rightResetButton.widthAnchor.constraint(equalToConstant: 60),

      rightChangeButton.centerYAnchor.constraint(equalTo: rightShortcutLabel.centerYAnchor),
      rightChangeButton.trailingAnchor.constraint(
        equalTo: rightResetButton.leadingAnchor, constant: -8),
      rightChangeButton.widthAnchor.constraint(equalToConstant: 100),

      rightHintLabel.topAnchor.constraint(equalTo: rightShortcutLabel.bottomAnchor, constant: 4),
      rightHintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      rightHintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

      restoreDefaultsButton.topAnchor.constraint(
        equalTo: rightHintLabel.bottomAnchor, constant: 24),
      restoreDefaultsButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
      restoreDefaultsButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),

      statusLabel.centerYAnchor.constraint(equalTo: restoreDefaultsButton.centerYAnchor),
      statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
      statusLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: restoreDefaultsButton.trailingAnchor, constant: 16),
    ])
  }

  private func bindStore() {
    store.$leftHotkey
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateUI()
      }
      .store(in: &cancellables)

    store.$rightHotkey
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateUI()
      }
      .store(in: &cancellables)
  }

  private func updateUI() {
    leftShortcutLabel.stringValue = store.leftHotkey.displayString
    rightShortcutLabel.stringValue = store.rightHotkey.displayString

    let leftRecording = recordingIdentifier == .left
    let rightRecording = recordingIdentifier == .right

    leftChangeButton.title = leftRecording ? "Press shortcut…" : "Change…"
    rightChangeButton.title = rightRecording ? "Press shortcut…" : "Change…"

    leftChangeButton.isEnabled = !rightRecording
    rightChangeButton.isEnabled = !leftRecording

    leftHintLabel.isHidden = !leftRecording
    rightHintLabel.isHidden = !rightRecording
  }

  @objc private func leftChangeClicked() {
    toggleRecording(for: .left)
  }

  @objc private func leftResetClicked() {
    reset(.left)
  }

  @objc private func rightChangeClicked() {
    toggleRecording(for: .right)
  }

  @objc private func rightResetClicked() {
    reset(.right)
  }

  @objc private func restoreDefaultsClicked() {
    restoreDefaults()
  }

  private func toggleRecording(for identifier: HotkeyIdentifier) {
    let shouldBegin = recordingIdentifier != identifier
    HotkeyRecorder.shared.endRecording()

    guard shouldBegin else {
      recordingIdentifier = nil
      setStatus("Cancelled recording.", color: .secondaryLabelColor)
      updateUI()
      return
    }

    recordingIdentifier = identifier
    setStatus("Waiting for new shortcut…", color: .secondaryLabelColor)
    updateUI()

    HotkeyRecorder.shared.beginRecording(for: identifier) { [weak self] combination in
      self?.handleRecordingResult(combination, for: identifier)
    } cancellation: { [weak self] in
      self?.recordingIdentifier = nil
      self?.setStatus("Cancelled recording.", color: .secondaryLabelColor)
      self?.updateUI()
    }
  }

  private func handleRecordingResult(
    _ combination: HotkeyCombination, for identifier: HotkeyIdentifier
  ) {
    let otherIdentifier = identifier.other
    if store.combination(for: otherIdentifier) == combination {
      NSSound.beep()
      setStatus("Shortcut already used for \(otherIdentifier.displayName).", color: .systemRed)
      recordingIdentifier = nil
      updateUI()
      return
    }

    store.update(combination, for: identifier)
    setStatus("Updated \(identifier.displayName) shortcut.", color: .labelColor)
    recordingIdentifier = nil
    updateUI()
  }

  private func reset(_ identifier: HotkeyIdentifier) {
    switch identifier {
    case .left:
      store.update(.defaultLeft, for: .left)
    case .right:
      store.update(.defaultRight, for: .right)
    case .space1:
      store.update(.defaultForSpace(1), for: .space1)
    case .space2:
      store.update(.defaultForSpace(2), for: .space2)
    case .space3:
      store.update(.defaultForSpace(3), for: .space3)
    case .space4:
      store.update(.defaultForSpace(4), for: .space4)
    case .space5:
      store.update(.defaultForSpace(5), for: .space5)
    case .space6:
      store.update(.defaultForSpace(6), for: .space6)
    case .space7:
      store.update(.defaultForSpace(7), for: .space7)
    case .space8:
      store.update(.defaultForSpace(8), for: .space8)
    case .space9:
      store.update(.defaultForSpace(9), for: .space9)
    case .space10:
      store.update(.defaultForSpace(10), for: .space10)
    case .lastSpace:
      store.update(.defaultLastSpace, for: .lastSpace)
    }
    setStatus("Reset \(identifier.displayName) shortcut.", color: .labelColor)
  }

  private func restoreDefaults() {
    store.resetToDefaults()
    setStatus("Restored default shortcuts.", color: .labelColor)
    recordingIdentifier = nil
    updateUI()
  }

  private func setStatus(_ message: String, color: NSColor) {
    statusLabel.stringValue = message
    statusLabel.textColor = color
  }
}

extension HotkeyIdentifier {
  fileprivate var other: HotkeyIdentifier {
    switch self {
    case .left: return .right
    case .right: return .left
    default: return .left
    }
  }
}
