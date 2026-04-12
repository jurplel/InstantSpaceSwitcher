import AppKit

final class SpacesSettingsViewController: NSViewController {
  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let mapping = SpaceDisplayMapping.shared

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    setupTableView()
  }

  private func setupTableView() {
    let spaceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("space"))
    spaceColumn.title = "Space"
    spaceColumn.width = 200
    tableView.addTableColumn(spaceColumn)

    let displayColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("display"))
    displayColumn.title = "Display"
    displayColumn.width = 300
    tableView.addTableColumn(displayColumn)

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
      title: "Reset All Displays", target: self, action: #selector(resetAll))
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

  private func availableDisplays() -> [(id: CGDirectDisplayID, name: String)] {
    return NSScreen.screens.enumerated().map { index, screen in
      let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
      let name = "Display \(index + 1): \(screen.localizedName)"
      return (id: displayID, name: name)
    }
  }

  @objc private func displayChanged(_ sender: NSPopUpButton) {
    let slot = sender.tag
    let selectedIndex = sender.indexOfSelectedItem

    if selectedIndex == 0 {
      mapping.setDisplayID(0, forSpaceSlot: slot)
    } else {
      let displays = availableDisplays()
      if selectedIndex - 1 < displays.count {
        mapping.setDisplayID(displays[selectedIndex - 1].id, forSpaceSlot: slot)
      }
    }
  }

  @objc private func resetAll() {
    mapping.resetAll()
    tableView.reloadData()
  }
}

extension SpacesSettingsViewController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    return 10
  }
}

extension SpacesSettingsViewController: NSTableViewDelegate {
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    let slot = row + 1

    if tableColumn?.identifier.rawValue == "space" {
      let cellView = NSTableCellView()
      let textField = NSTextField(labelWithString: "Space \(slot)")
      textField.translatesAutoresizingMaskIntoConstraints = false
      cellView.addSubview(textField)
      cellView.textField = textField

      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    } else if tableColumn?.identifier.rawValue == "display" {
      let cellView = NSView()

      let popup = NSPopUpButton()
      popup.translatesAutoresizingMaskIntoConstraints = false
      popup.tag = slot
      popup.target = self
      popup.action = #selector(displayChanged(_:))
      popup.controlSize = .small
      popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

      popup.addItem(withTitle: "Current Display")

      let displays = availableDisplays()
      for display in displays {
        popup.addItem(withTitle: display.name)
      }

      let currentDisplayID = mapping.displayID(forSpaceSlot: slot)
      if currentDisplayID == 0 {
        popup.selectItem(at: 0)
      } else if let displayIndex = displays.firstIndex(where: { $0.id == currentDisplayID }) {
        popup.selectItem(at: displayIndex + 1)
      } else {
        popup.selectItem(at: 0)
      }

      cellView.addSubview(popup)

      NSLayoutConstraint.activate([
        popup.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
        popup.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
        popup.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
      ])

      return cellView
    }

    return nil
  }
}
