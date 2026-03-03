import AppKit
import Combine

private class RecordingView: NSView {
  override var acceptsFirstResponder: Bool { true }
  override func becomeFirstResponder() -> Bool { true }
}

final class KeyboardShortcutsViewController: NSViewController {
  private let store = HotkeyStore.shared
  private var cancellables = Set<AnyCancellable>()
  private var recordingIdentifier: HotkeyIdentifier?
  private var recordingButton: NSButton?

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()

  private struct ShortcutRow {
    let identifier: HotkeyIdentifier
    let name: String
    var combination: HotkeyCombination
    var isEnabled: Bool
  }

  private var shortcuts: [ShortcutRow] = []

  override func loadView() {
    view = RecordingView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    setupTableView()
    loadShortcuts()
    bindStore()
  }

  private func setupTableView() {
    let enabledColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
    enabledColumn.title = "Enabled"
    enabledColumn.width = 80
    tableView.addTableColumn(enabledColumn)

    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.title = "Action"
    nameColumn.width = 180
    tableView.addTableColumn(nameColumn)

    let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
    shortcutColumn.title = "Shortcut"
    shortcutColumn.width = 210
    tableView.addTableColumn(shortcutColumn)

    tableView.delegate = self
    tableView.dataSource = self
    tableView.rowHeight = 28
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .bezelBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let resetAllButton = NSButton(
      title: "Reset All to Defaults", target: self, action: #selector(resetAllShortcuts))
    resetAllButton.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(scrollView)
    view.addSubview(resetAllButton)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scrollView.bottomAnchor.constraint(equalTo: resetAllButton.topAnchor, constant: -12),

      resetAllButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      resetAllButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }

  private func loadShortcuts() {
    shortcuts = [
      ShortcutRow(
        identifier: .left, name: "Switch to space on the left", combination: store.leftHotkey,
        isEnabled: store.isEnabled(.left)),
      ShortcutRow(
        identifier: .right, name: "Switch to space on the right", combination: store.rightHotkey,
        isEnabled: store.isEnabled(.right)),
      ShortcutRow(
        identifier: .space1, name: "Switch to space 1", combination: store.space1Hotkey,
        isEnabled: store.isEnabled(.space1)),
      ShortcutRow(
        identifier: .space2, name: "Switch to space 2", combination: store.space2Hotkey,
        isEnabled: store.isEnabled(.space2)),
      ShortcutRow(
        identifier: .space3, name: "Switch to space 3", combination: store.space3Hotkey,
        isEnabled: store.isEnabled(.space3)),
      ShortcutRow(
        identifier: .space4, name: "Switch to space 4", combination: store.space4Hotkey,
        isEnabled: store.isEnabled(.space4)),
      ShortcutRow(
        identifier: .space5, name: "Switch to space 5", combination: store.space5Hotkey,
        isEnabled: store.isEnabled(.space5)),
      ShortcutRow(
        identifier: .space6, name: "Switch to space 6", combination: store.space6Hotkey,
        isEnabled: store.isEnabled(.space6)),
      ShortcutRow(
        identifier: .space7, name: "Switch to space 7", combination: store.space7Hotkey,
        isEnabled: store.isEnabled(.space7)),
      ShortcutRow(
        identifier: .space8, name: "Switch to space 8", combination: store.space8Hotkey,
        isEnabled: store.isEnabled(.space8)),
      ShortcutRow(
        identifier: .space9, name: "Switch to space 9", combination: store.space9Hotkey,
        isEnabled: store.isEnabled(.space9)),
      ShortcutRow(
        identifier: .space10, name: "Switch to space 10", combination: store.space10Hotkey,
        isEnabled: store.isEnabled(.space10)),
    ]
    tableView.reloadData()
  }

  private func bindStore() {
    store.$leftHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$rightHotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space1Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space2Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space3Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space4Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space5Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space6Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space7Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space8Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space9Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
    store.$space10Hotkey.receive(on: RunLoop.main).sink { [weak self] _ in self?.loadShortcuts() }
      .store(in: &cancellables)
  }
}

extension KeyboardShortcutsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return shortcuts.count
  }
}

extension KeyboardShortcutsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let shortcut = shortcuts[row]

    if tableColumn?.identifier.rawValue == "enabled" {
      let cellView = NSTableCellView()
      let checkbox = NSButton(
        checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
      checkbox.state = shortcut.isEnabled ? .on : .off
      checkbox.tag = row
      checkbox.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(checkbox)

      NSLayoutConstraint.activate([
        checkbox.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
        checkbox.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    } else if tableColumn?.identifier.rawValue == "name" {
      let cellView = NSTableCellView()
      let textField = NSTextField(labelWithString: shortcut.name)
      textField.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(textField)
      cellView.textField = textField

      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    } else if tableColumn?.identifier.rawValue == "shortcut" {
      let cellView = NSView()

      let recorder = ShortcutRecorderControl(frame: NSRect(x: 0, y: 0, width: 150, height: 22))
      recorder.currentShortcut = shortcut.combination
      recorder.translatesAutoresizingMaskIntoConstraints = false
      recorder.onRecordingComplete = { [weak self] combination in
        self?.handleRecordingResult(combination, for: shortcut.identifier)
      }
      recorder.onRecordingCancelled = {
        print("[KeyboardShortcuts] Recording cancelled")
      }
      cellView.addSubview(recorder)

      let resetButton = NSButton(
        image: NSImage(
          systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")!,
        target: self, action: #selector(resetShortcut(_:)))
      resetButton.bezelStyle = .rounded
      resetButton.isBordered = false
      resetButton.tag = row
      resetButton.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(resetButton)

      NSLayoutConstraint.activate([
        recorder.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        recorder.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        recorder.widthAnchor.constraint(equalToConstant: 150),
        recorder.heightAnchor.constraint(equalToConstant: 22),

        resetButton.leadingAnchor.constraint(equalTo: recorder.trailingAnchor, constant: 8),
        resetButton.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        resetButton.widthAnchor.constraint(equalToConstant: 24),
        resetButton.heightAnchor.constraint(equalToConstant: 24),
      ])

      return cellView
    }

    return nil
  }

  @objc private func resetShortcut(_ sender: NSButton) {
    let row = sender.tag
    guard row < shortcuts.count else { return }

    let identifier = shortcuts[row].identifier
    let defaultCombination: HotkeyCombination
    switch identifier {
    case .left: defaultCombination = .defaultLeft
    case .right: defaultCombination = .defaultRight
    case .space1: defaultCombination = .defaultForSpace(1)
    case .space2: defaultCombination = .defaultForSpace(2)
    case .space3: defaultCombination = .defaultForSpace(3)
    case .space4: defaultCombination = .defaultForSpace(4)
    case .space5: defaultCombination = .defaultForSpace(5)
    case .space6: defaultCombination = .defaultForSpace(6)
    case .space7: defaultCombination = .defaultForSpace(7)
    case .space8: defaultCombination = .defaultForSpace(8)
    case .space9: defaultCombination = .defaultForSpace(9)
    case .space10: defaultCombination = .defaultForSpace(10)
    }
    store.update(defaultCombination, for: identifier)
  }

  @objc private func resetAllShortcuts() {
    store.resetToDefaults()
  }

  @objc private func toggleEnabled(_ sender: NSButton) {
    let row = sender.tag
    guard row < shortcuts.count else { return }

    let identifier = shortcuts[row].identifier
    store.setEnabled(sender.state == .on, for: identifier)
  }

  private func handleRecordingResult(
    _ combination: HotkeyCombination, for identifier: HotkeyIdentifier
  ) {
    let otherIdentifier: HotkeyIdentifier = identifier == .left ? .right : .left
    if store.combination(for: otherIdentifier) == combination {
      NSSound.beep()
      let alert = NSAlert()
      alert.messageText = "Shortcut already in use"
      alert.informativeText = "This shortcut is already assigned to another action."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      alert.runModal()
      return
    }

    store.update(combination, for: identifier)
  }
}
