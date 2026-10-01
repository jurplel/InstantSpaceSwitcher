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
    let animationTab = NSTabViewItem(viewController: AnimationSettingsViewController())
    animationTab.label = "Animation"
    animationTab.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Animation")
    addTabViewItem(animationTab)
    addTabViewItem(shortcutsTab)
  }
}
