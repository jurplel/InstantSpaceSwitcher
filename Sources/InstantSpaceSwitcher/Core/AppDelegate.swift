import AppKit
import ApplicationServices
import Combine
import ISS

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let menuBarController = MenuBarController()
  private let hotkeyStore = HotkeyStore.shared
  private lazy var preferencesWindowController = PreferencesWindowController()
  private var currentSpaceIndex: UInt32?
  private var lastSpaceIndex: UInt32?
  private var cancellables = Set<AnyCancellable>()
  private var spaceChangeObserver: Any?
  private var appActivationObserver: Any?

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleReopen),
      forEventClass: kCoreEventClass,
      andEventID: kAEReopenApplication
    )
  }

  @objc private func handleReopen(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
    preferencesWindowController.present()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    ensureAccessibilityPermission()

    if !iss_init() {
      print("Failed to initialize ISS event tap")
      retryIssInit()
    }

    if UserDefaults.standard.bool(forKey: "swipeOverride") {
      iss_set_swipe_override(true)
    }

    let gestureSpeed = UserDefaults.standard.double(forKey: "gestureSpeed")
    if gestureSpeed > 0 {
      iss_set_gesture_speed(gestureSpeed)
    }

    if UserDefaults.standard.object(forKey: "overlayDetectionEnabled") as? Bool ?? true {
      iss_set_overlay_detection_enabled(true)
    }

    _ = SpaceNameStore.shared
    SpaceCatalog.shared.startObserving()
    iss_set_switch_event_callback { event in
      DispatchQueue.main.async {
        OSDWindow.shared.show(
          message: SpaceNameStore.shared.message(for: event), screenID: event.display.screenID)
      }
    }

    setupMainMenu()
    menuBarController.delegate = self
    menuBarController.setup()

    if UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
      menuBarController.setIconVisible(false)
    }

    bindHotkeys()
    observeSpaceChanges()
    observeAppActivation()
    refreshSpaceInfo()

    if let appIcon = Bundle.main.image(forResource: "ISS") ?? NSImage(named: "ISS") {
      NSApp.applicationIconImage = appIcon
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    iss_set_switch_event_callback(nil)
    iss_destroy()
    stopObservingSpaceChanges()
    stopObservingAppActivation()
  }

  private func retryIssInit() {
    guard !iss_init() else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.retryIssInit()
    }
  }

  private func ensureAccessibilityPermission() {
    guard !AXIsProcessTrusted() else { return }

    if let bundleId = Bundle.main.bundleIdentifier {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
      task.arguments = ["reset", "Accessibility", bundleId]
      try? task.run()
      task.waitUntilExit()
    }

    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }

  private func setupMainMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu(title: Constants.appName)
    appMenuItem.submenu = appMenu

    let aboutItem = NSMenuItem(
      title: "About", action: #selector(openAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    appMenu.addItem(aboutItem)

    appMenu.addItem(NSMenuItem.separator())

    let preferencesItem = NSMenuItem(
      title: "Settings…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
    preferencesItem.target = self
    preferencesItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    appMenu.addItem(preferencesItem)

    appMenu.addItem(NSMenuItem.separator())

    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu()
    servicesItem.submenu = servicesMenu
    NSApp.servicesMenu = servicesMenu
    appMenu.addItem(servicesItem)

    appMenu.addItem(NSMenuItem.separator())

    let hideItem = NSMenuItem(
      title: "Hide \(Constants.appName)", action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h")
    hideItem.target = NSApp
    appMenu.addItem(hideItem)

    let hideOthersItem = NSMenuItem(
      title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h")
    hideOthersItem.keyEquivalentModifierMask = [.command, .option]
    hideOthersItem.target = NSApp
    appMenu.addItem(hideOthersItem)

    let showAllItem = NSMenuItem(
      title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: "")
    showAllItem.target = NSApp
    appMenu.addItem(showAllItem)

    appMenu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    quitItem.target = NSApp
    appMenu.addItem(quitItem)

    // File menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)

    let fileMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileMenu

    let closeItem = NSMenuItem(
      title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    fileMenu.addItem(closeItem)

    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redoItem.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redoItem)
    editMenu.addItem(NSMenuItem.separator())

    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(
      title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenu.addItem(NSMenuItem.separator())

    let emojiItem = NSMenuItem(
      title: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
      keyEquivalent: " ")
    emojiItem.keyEquivalentModifierMask = [.control, .command]
    emojiItem.target = NSApp
    editMenu.addItem(emojiItem)

    NSApp.mainMenu = mainMenu
  }

  @objc private func openPreferences(_ sender: Any?) {
    preferencesWindowController.present()
  }

  @objc private func openAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(sender)
    // Ensure window comes to front if already open
    NSApp.windows.first(where: { $0.title.contains("About") })?.makeKeyAndOrderFront(nil)
  }

  private func bindHotkeys() {
    hotkeyStore.$leftHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .left, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$rightHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .right, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space1Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space1, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space2Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space2, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space3Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space3, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space4Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space4, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space5Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space5, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space6Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space6, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space7Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space7, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space8Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space8, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space9Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space9, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space10Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space10, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space11Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space11, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space12Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space12, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space13Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space13, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space14Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space14, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space15Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space15, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$space16Hotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .space16, combination: $0)
    }.store(in: &cancellables)
    hotkeyStore.$spaceLastSpaceHotkey.receive(on: RunLoop.main).sink { [weak self] in
      self?.registerHotkey(for: .lastSpace, combination: $0)
    }.store(in: &cancellables)

    hotkeyStore.$enabledStates.receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self = self else { return }
      for identifier in HotkeyIdentifier.allCases {
        self.registerHotkey(
          for: identifier, combination: self.hotkeyStore.combination(for: identifier))
      }
    }.store(in: &cancellables)
  }

  func setMenuBarIconVisible(_ visible: Bool) {
    menuBarController.setIconVisible(visible)
  }

  func reregisterAllHotkeys() {
    for identifier in HotkeyIdentifier.allCases {
      let combination = hotkeyStore.combination(for: identifier)
      menuBarController.applyHotkey(combination, to: identifier)
      registerHotkey(for: identifier, combination: combination)
    }
  }

  private func registerHotkey(for identifier: HotkeyIdentifier, combination: HotkeyCombination) {
    menuBarController.applyHotkey(combination, to: identifier)

    guard hotkeyStore.isEnabled(identifier) else {
      HotKeyManager.shared.unregister(identifier: identifier)
      return
    }

    HotKeyManager.shared.register(identifier: identifier, combination: combination) { [weak self] in
      guard let self else { return }
      switch identifier {
      case .left:
        self.performSpaceSwitch(ISSDirectionLeft)
      case .right:
        self.performSpaceSwitch(ISSDirectionRight)
      case .space1:
        self.performSpaceSwitchToIndex(0)
      case .space2:
        self.performSpaceSwitchToIndex(1)
      case .space3:
        self.performSpaceSwitchToIndex(2)
      case .space4:
        self.performSpaceSwitchToIndex(3)
      case .space5:
        self.performSpaceSwitchToIndex(4)
      case .space6:
        self.performSpaceSwitchToIndex(5)
      case .space7:
        self.performSpaceSwitchToIndex(6)
      case .space8:
        self.performSpaceSwitchToIndex(7)
      case .space9:
        self.performSpaceSwitchToIndex(8)
      case .space10:
        self.performSpaceSwitchToIndex(9)
      case .space11:
        self.performSpaceSwitchToIndex(10)
      case .space12:
        self.performSpaceSwitchToIndex(11)
      case .space13:
        self.performSpaceSwitchToIndex(12)
      case .space14:
        self.performSpaceSwitchToIndex(13)
      case .space15:
        self.performSpaceSwitchToIndex(14)
      case .space16:
        self.performSpaceSwitchToIndex(15)
      case .lastSpace:
        self.performSpaceLastSpace()
      }
    }
  }

  private func performSpaceSwitch(_ direction: ISSDirection) {
    if !iss_switch(direction) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func performSpaceSwitchToIndex(_ index: UInt32) {
    if !iss_switch_to_index(index) {
      NSSound.beep()
      return
    }
    refreshSpaceInfo()
  }

  private func performSpaceLastSpace() {
    guard let lastSpaceIndex, lastSpaceIndex != currentSpaceIndex else {
      NSSound.beep()
      return
    }

    performSpaceSwitchToIndex(lastSpaceIndex)
  }

  private func refreshSpaceInfo() {
    var info = ISSSpaceInfo()
    if iss_get_menubar_space_info(&info) {
      if currentSpaceIndex != info.currentIndex {
        lastSpaceIndex = currentSpaceIndex
        currentSpaceIndex = info.currentIndex
      }

      menuBarController.updateWithSpaceInfo(info)
    } else {
      menuBarController.updateWithSpaceInfo(nil)
    }
  }

  private func observeSpaceChanges() {
    stopObservingSpaceChanges()
    spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshSpaceInfo()
        iss_reset_predictions()
        self.menuBarController.scheduleRefresh(after: 0.2)
      }
    }
  }

  private func stopObservingSpaceChanges() {
    if let observer = spaceChangeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      spaceChangeObserver = nil
    }
  }

  private func observeAppActivation() {
    stopObservingAppActivation()
    appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.menuBarController.scheduleRefresh(after: 0.1)
      }
    }
  }

  private func stopObservingAppActivation() {
    if let observer = appActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
      appActivationObserver = nil
    }
  }

}

extension AppDelegate: MenuBarControllerDelegate {
  func menuBarControllerDidRequestSwitchLeft(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionLeft)
  }

  func menuBarControllerDidRequestSwitchRight(_ controller: MenuBarController) {
    performSpaceSwitch(ISSDirectionRight)
  }

  func menuBarControllerDidRequestPreferences(_ controller: MenuBarController) {
    preferencesWindowController.present()
  }

  func menuBarController(
    _ controller: MenuBarController, didRequestSwitchToSpaceAtIndex index: UInt32
  ) {
    if !iss_switch_to_index(index) {
      NSSound.beep()
    }
    controller.scheduleRefresh(after: 0.25)
  }

  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController) {
    refreshSpaceInfo()
  }
}
