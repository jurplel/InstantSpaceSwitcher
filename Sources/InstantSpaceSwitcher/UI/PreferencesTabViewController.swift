import AppKit

final class PreferencesTabViewController: NSTabViewController {
  override func viewDidLoad() {
    super.viewDidLoad()

    tabStyle = .toolbar

    let generalTab = NSTabViewItem(viewController: GeneralSettingsViewController())
    generalTab.label = "General"
    generalTab.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")

    let shortcutsTab = NSTabViewItem(viewController: KeyboardShortcutsViewController())
    shortcutsTab.label = "Keyboard"
    shortcutsTab.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard")

    let spacesTab = NSTabViewItem(viewController: SpaceNamesViewController())
    spacesTab.label = "Spaces"
    spacesTab.image = NSImage(
      systemSymbolName: "square.and.line.vertical.and.square",
      accessibilityDescription: "Spaces")

    addTabViewItem(generalTab)
    addTabViewItem(shortcutsTab)
    addTabViewItem(spacesTab)
  }
}
