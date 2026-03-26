import AppKit
import ISS

final class SpaceNamesViewController: NSViewController {
  private let store = SpaceNameStore.shared
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private var pollTimer: Timer?

  /// Each entry is either a display header or a space row.
  private enum Row {
    case displayHeader(displayIndex: Int, displayID: UInt32)
    case space(displayID: UInt32, spaceIndex: Int)
  }

  private var rows: [Row] = []

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupTableView()
    refreshDisplayInfo()
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    refreshDisplayInfo()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      self?.refreshDisplayInfo()
    }
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    pollTimer?.invalidate()
    pollTimer = nil
  }

  private func refreshDisplayInfo() {
    var info = ISSAllDisplaysInfo()
    guard iss_get_all_displays_info(&info) else { return }

    var newRows: [Row] = []
    let displayCount = Int(info.displayCount)

    for di in 0..<displayCount {
      let displayID = withUnsafePointer(to: &info.displayIDs) {
        $0.withMemoryRebound(to: UInt32.self, capacity: Int(ISS_MAX_DISPLAYS)) { $0[di] }
      }
      let spaceCount = withUnsafePointer(to: &info.spaceCounts) {
        Int($0.withMemoryRebound(to: UInt32.self, capacity: Int(ISS_MAX_DISPLAYS)) { $0[di] })
      }

      newRows.append(.displayHeader(displayIndex: di, displayID: displayID))
      for si in 0..<spaceCount {
        newRows.append(.space(displayID: displayID, spaceIndex: si))
      }

      // Clear stale names beyond current space count
      store.clearNames(forDisplayID: displayID, beyondCount: spaceCount)
    }

    // Only reload if structure changed
    if newRows.count != rows.count {
      rows = newRows
      tableView.reloadData()
    } else {
      rows = newRows
    }
  }

  private func setupTableView() {
    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.title = "Space"
    nameColumn.width = 120
    nameColumn.isEditable = false
    tableView.addTableColumn(nameColumn)

    let customNameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("customName"))
    customNameColumn.title = "Custom Name"
    customNameColumn.width = 380
    tableView.addTableColumn(customNameColumn)

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

    let resetButton = NSButton(
      title: "Reset All Names", target: self, action: #selector(resetAll))
    resetButton.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(scrollView)
    view.addSubview(resetButton)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scrollView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -12),

      resetButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      resetButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }

  @objc private func resetAll() {
    store.resetAll()
    tableView.reloadData()
  }
}

extension SpaceNamesViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return rows.count
  }
}

extension SpaceNamesViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .displayHeader = rows[row] { return true }
    return false
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    let entry = rows[row]

    switch entry {
    case .displayHeader(let displayIndex, _):
      // Group rows span all columns — only called once with tableColumn == nil or first column
      guard tableColumn == nil || tableColumn?.identifier.rawValue == "name" else { return nil }
      let cellView = NSTableCellView()
      let label = NSTextField(labelWithString: "Display \(displayIndex + 1)")
      label.font = NSFont.boldSystemFont(ofSize: 13)
      label.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(label)

      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView

    case .space(_, let spaceIndex):
      if tableColumn?.identifier.rawValue == "name" {
        let cellView = NSTableCellView()
        let textField = NSTextField(labelWithString: "Space \(spaceIndex + 1)")
        textField.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(textField)
        cellView.textField = textField

        NSLayoutConstraint.activate([
          textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 16),
          textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
          textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])

        return cellView
      } else if tableColumn?.identifier.rawValue == "customName" {
        guard case .space(let displayID, let spaceIndex) = entry else { return nil }
        let cellView = NSTableCellView()
        let textField = NSTextField()
        textField.stringValue = store.name(forDisplayID: displayID, spaceIndex: spaceIndex) ?? ""
        textField.placeholderString = "Enter name\u{2026}"
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.tag = row
        textField.delegate = self
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.cell?.lineBreakMode = .byClipping
        textField.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(textField)
        cellView.textField = textField

        NSLayoutConstraint.activate([
          textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
          textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
          textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])

        return cellView
      }
    }

    return nil
  }
}

extension SpaceNamesViewController: NSTextFieldDelegate {
  func controlTextDidEndEditing(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField else { return }
    let rowIndex = textField.tag
    guard rowIndex >= 0 && rowIndex < rows.count else { return }
    guard case .space(let displayID, let spaceIndex) = rows[rowIndex] else { return }
    let value = textField.stringValue.trimmingCharacters(in: .whitespaces)
    store.setName(value.isEmpty ? nil : value, forDisplayID: displayID, spaceIndex: spaceIndex)
  }
}
