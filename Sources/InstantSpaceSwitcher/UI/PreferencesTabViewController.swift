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

    addTabViewItem(generalTab)
    addTabViewItem(shortcutsTab)
    let spacesTab = NSTabViewItem(viewController: SpaceNamesViewController())
    spacesTab.label = "Spaces"
    spacesTab.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Spaces")
    addTabViewItem(spacesTab)
  }
}
