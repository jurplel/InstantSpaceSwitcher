import AppKit
import ISS

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
  private(set) var statusItem: NSStatusItem!
  private var leftMenuItem: NSMenuItem?
  private var rightMenuItem: NSMenuItem?
  private var spacesMenuItem: NSMenuItem?
  private var cachedSpaceInfo: ISSSpaceInfo?
  private var refreshWorkItem: DispatchWorkItem?

  private lazy var baseStatusImage: NSImage? = {
    let image = NSImage(
      systemSymbolName: "arrow.left.and.right.square", accessibilityDescription: Constants.appName)
    image?.isTemplate = true
    return image
  }()

  weak var delegate: MenuBarControllerDelegate?

  func setup() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.menu = createMenu()
    updateStatusItemAppearance()
  }

  private func createMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self

    let leftItem = NSMenuItem(
      title: "Switch Left", action: #selector(switchLeft(_:)), keyEquivalent: "")
    leftItem.target = self
    leftItem.image = NSImage(systemSymbolName: "arrow.left", accessibilityDescription: nil)
    menu.addItem(leftItem)
    leftMenuItem = leftItem

    let rightItem = NSMenuItem(
      title: "Switch Right", action: #selector(switchRight(_:)), keyEquivalent: "")
    rightItem.target = self
    rightItem.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
    menu.addItem(rightItem)
    rightMenuItem = rightItem

    menu.addItem(NSMenuItem.separator())

    let spacesItem = NSMenuItem(title: "Spaces", action: nil, keyEquivalent: "")
    let spacesSubmenu = NSMenu(title: "Spaces")
    spacesSubmenu.delegate = self
    spacesSubmenu.autoenablesItems = false
    spacesItem.submenu = spacesSubmenu
    spacesItem.image = NSImage(
      systemSymbolName: "square.and.line.vertical.and.square", accessibilityDescription: nil)
    menu.addItem(spacesItem)
    spacesMenuItem = spacesItem

    menu.addItem(NSMenuItem.separator())

    let preferencesItem = NSMenuItem(
      title: "Settings…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
    preferencesItem.keyEquivalentModifierMask = [.command]
    preferencesItem.target = self
    preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    menu.addItem(preferencesItem)

    menu.addItem(NSMenuItem.separator())

    let aboutItem = NSMenuItem(
      title: "About \(Constants.appName)", action: #selector(openAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    menu.addItem(aboutItem)

    let quitItem = NSMenuItem(
      title: "Quit \(Constants.appName)", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    menu.addItem(quitItem)

    return menu
  }

  @objc private func switchLeft(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestSwitchLeft(self)
  }

  @objc private func switchRight(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestSwitchRight(self)
  }

  @objc private func openPreferences(_ sender: Any?) {
    delegate?.menuBarControllerDidRequestPreferences(self)
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(sender)
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  @objc private func switchToSpace(_ sender: NSMenuItem) {
    let targetIndex = UInt32(sender.tag)
    delegate?.menuBarController(self, didRequestSwitchToSpaceAtIndex: targetIndex)
  }

  func updateWithSpaceInfo(_ info: ISSSpaceInfo?) {
    cachedSpaceInfo = info
    updateMenuState()
  }

  func scheduleRefresh(after delay: TimeInterval) {
    refreshWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.delegate?.menuBarControllerDidRequestRefresh(self)
    }
    refreshWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
  }

  private func updateMenuState() {
    if let info = cachedSpaceInfo {
      leftMenuItem?.isEnabled = info.currentIndex > 0
      rightMenuItem?.isEnabled = info.currentIndex + 1 < info.spaceCount
    } else {
      leftMenuItem?.isEnabled = true
      rightMenuItem?.isEnabled = true
    }

    updateSpacesMenuItems()
    updateStatusItemAppearance()
  }

  private func updateSpacesMenuItems() {
    guard let submenu = spacesMenuItem?.submenu else { return }
    submenu.removeAllItems()

    guard let info = cachedSpaceInfo, info.spaceCount > 0 else {
      let item = NSMenuItem(title: "No accessible spaces", action: nil, keyEquivalent: "")
      item.isEnabled = false
      submenu.addItem(item)
      return
    }

    // Menu bar shows spaces for the cursor's current display
    let spaceIDs = AppDelegate.cursorDisplaySpaceIDs()
    let count = Int(info.spaceCount)
    for index in 0..<count {
      let spaceID = index < spaceIDs.count ? spaceIDs[index] : 0
      let customName = SpaceNameStore.shared.name(forSpaceID: spaceID)
      let title = customName ?? "Space \(index + 1)"
      let item = NSMenuItem(title: title, action: #selector(switchToSpace(_:)), keyEquivalent: "")
      item.tag = index
      item.target = self
      item.state = index == Int(info.currentIndex) ? .on : .off
      submenu.addItem(item)
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu === statusItem.menu || menu === spacesMenuItem?.submenu {
      scheduleRefresh(after: 0.05)
    }
  }

  func menuWillOpen(_ menu: NSMenu) {
    if menu === statusItem.menu || menu === spacesMenuItem?.submenu {
      scheduleRefresh(after: 0.05)
    }
  }

  private func updateStatusItemAppearance() {
    guard let button = statusItem.button else { return }

    button.font = nil
    button.title = ""
    button.imagePosition = .imageOnly

    let icon: NSImage?
    if let info = cachedSpaceInfo {
      icon = MenuBarIconRenderer.renderIcon(for: info)
    } else {
      icon = nil
    }

    let finalIcon = icon ?? baseStatusImage
    finalIcon?.isTemplate = true
    button.image = finalIcon
  }

  func applyHotkey(_ combination: HotkeyCombination, to identifier: HotkeyIdentifier) {
    let menuItem = identifier == .left ? leftMenuItem : rightMenuItem
    guard let menuItem else { return }
    menuItem.keyEquivalent = combination.keyEquivalent
    menuItem.keyEquivalentModifierMask = combination.cocoaModifierFlags
  }
}

@MainActor
protocol MenuBarControllerDelegate: AnyObject {
  func menuBarControllerDidRequestSwitchLeft(_ controller: MenuBarController)
  func menuBarControllerDidRequestSwitchRight(_ controller: MenuBarController)
  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController)
  func menuBarController(
    _ controller: MenuBarController, didRequestSwitchToSpaceAtIndex index: UInt32)
  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController)
}
