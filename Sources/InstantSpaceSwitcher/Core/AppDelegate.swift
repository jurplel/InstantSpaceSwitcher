import AppKit
import ApplicationServices
import Combine
import ISS
import OSLog
import SpaceTransition

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
  private var transitionCoordinator = SpaceTransitionCoordinator()
  private var transitionTimeoutWorkItem: DispatchWorkItem?
  private var recoveryWorkItem: DispatchWorkItem?
  private let transitionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.interversehq.InstantSpaceSwitcher",
    category: "space-transition"
  )
  private let transitionTimeout: TimeInterval = 1.0
  private let recoveryInterval: TimeInterval = 1.0

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

    iss_set_swipe_callback { direction in
      DispatchQueue.main.async {
        (NSApp.delegate as? AppDelegate)?.performSpaceSwitch(direction)
      }
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
  }

  func applicationWillTerminate(_ notification: Notification) {
    transitionTimeoutWorkItem?.cancel()
    recoveryWorkItem?.cancel()
    iss_set_swipe_callback(nil)
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
      case .lastSpace:
        self.performSpaceLastSpace()
      }
    }
  }

  private func performSpaceSwitch(_ direction: ISSDirection) {
    let coordinatorDirection: SpaceTransitionCoordinator.Direction =
      direction == ISSDirectionLeft ? .left : .right
    let transitionActive = transitionCoordinator.isTransitionInFlight
      || transitionCoordinator.isRecovering
    let snapshot = transitionActive ? nil : loadSpaceSnapshot()
    handleTransitionEffects(
      transitionCoordinator.request(coordinatorDirection, snapshot: snapshot)
    )
  }

  private func performSpaceSwitchToIndex(_ index: UInt32) {
    guard !transitionCoordinator.isTransitionInFlight,
      !transitionCoordinator.isRecovering
    else {
      transitionLogger.notice(
        "event=request_rejected reason=transition_active target=\(index, privacy: .public)"
      )
      NSSound.beep()
      return
    }

    guard let snapshot = loadSpaceSnapshot(), Int(index) < snapshot.spaceCount else {
      transitionLogger.error("event=request_failed reason=target_unavailable target=\(index, privacy: .public)")
      NSSound.beep()
      return
    }

    let targetIndex = Int(index)
    let projectedIndex = transitionCoordinator.projectedIndex(from: snapshot)
    guard targetIndex != projectedIndex else { return }

    let direction: SpaceTransitionCoordinator.Direction =
      targetIndex < projectedIndex ? .left : .right
    for _ in 0..<abs(targetIndex - projectedIndex) {
      handleTransitionEffects(transitionCoordinator.request(direction, snapshot: snapshot))
    }
  }

  private func performSpaceLastSpace() {
    guard let lastSpaceIndex, lastSpaceIndex != currentSpaceIndex else {
      NSSound.beep()
      return
    }

    performSpaceSwitchToIndex(lastSpaceIndex)
  }

  private func loadSpaceSnapshot() -> SpaceTransitionCoordinator.SpaceSnapshot? {
    var info = ISSSpaceInfo()
    guard iss_get_space_info(&info) else { return nil }

    let displayID = withUnsafeBytes(of: &info.displayID) { bytes -> String in
      guard let baseAddress = bytes.baseAddress else { return "" }
      return String(cString: baseAddress.assumingMemoryBound(to: CChar.self))
    }
    guard !displayID.isEmpty else { return nil }

    return SpaceTransitionCoordinator.SpaceSnapshot(
      displayID: displayID,
      currentIndex: Int(info.currentIndex),
      spaceCount: Int(info.spaceCount)
    )
  }

  private func handleTransitionEffects(
    _ effects: [SpaceTransitionCoordinator.Effect]
  ) {
    for effect in effects {
      switch effect {
      case .requested(let direction, let queueDepth):
        transitionLogger.info(
          "event=request direction=\(direction.rawValue, privacy: .public) queue_depth=\(queueDepth, privacy: .public)"
        )

      case .start(let transition, let queueDepth):
        startTransition(transition, queueDepth: queueDepth)

      case .confirmed(let transition, let queueDepth):
        transitionTimeoutWorkItem?.cancel()
        transitionTimeoutWorkItem = nil
        iss_reset_predictions()
        refreshSpaceInfo()
        if !transitionCoordinator.isTransitionInFlight {
          OSDWindow.shared.show(message: "\(transition.targetIndex + 1)")
        }
        transitionLogger.info(
          "event=confirmation id=\(transition.id, privacy: .public) direction=\(transition.direction.rawValue, privacy: .public) target=\(transition.targetIndex, privacy: .public) queue_depth=\(queueDepth, privacy: .public)"
        )

      case .blocked(let direction, let queueDepth):
        transitionLogger.info(
          "event=request_blocked direction=\(direction.rawValue, privacy: .public) queue_depth=\(queueDepth, privacy: .public)"
        )
        NSSound.beep()

      case .ignoredConfirmation(let transitionID):
        transitionLogger.debug(
          "event=notification_ignored id=\(transitionID ?? 0, privacy: .public)"
        )

      case .timedOut(let transition, let droppedQueueDepth):
        transitionTimeoutWorkItem?.cancel()
        transitionTimeoutWorkItem = nil
        transitionLogger.error(
          "event=timeout id=\(transition.id, privacy: .public) direction=\(transition.direction.rawValue, privacy: .public) source=\(transition.sourceIndex, privacy: .public) target=\(transition.targetIndex, privacy: .public) dropped_queue_depth=\(droppedQueueDepth, privacy: .public)"
        )
        beginRecovery(for: transition.id)

      case .injectionFailed(let transition, let droppedQueueDepth):
        transitionTimeoutWorkItem?.cancel()
        transitionTimeoutWorkItem = nil
        transitionLogger.error(
          "event=injection_failed id=\(transition.id, privacy: .public) direction=\(transition.direction.rawValue, privacy: .public) dropped_queue_depth=\(droppedQueueDepth, privacy: .public)"
        )
        beginRecovery(for: transition.id)
        NSSound.beep()

      case .spaceInfoUnavailable(let direction):
        transitionLogger.error(
          "event=request_failed reason=space_info_unavailable direction=\(direction.rawValue, privacy: .public)"
        )
        NSSound.beep()

      case .rejectedDuringRecovery(let direction):
        transitionLogger.notice(
          "event=request_rejected reason=recovery direction=\(direction.rawValue, privacy: .public)"
        )
        NSSound.beep()

      case .reconciled(let transitionID):
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        iss_reset_predictions()
        refreshSpaceInfo()
        transitionLogger.notice(
          "event=reconciliation id=\(transitionID, privacy: .public) status=ready"
        )
      }
    }
  }

  private func startTransition(
    _ transition: SpaceTransitionCoordinator.Transition,
    queueDepth: Int
  ) {
    OSDWindow.shared.hideForSpaceTransition()
    scheduleTimeout(for: transition.id)
    transitionLogger.info(
      "event=start id=\(transition.id, privacy: .public) direction=\(transition.direction.rawValue, privacy: .public) source=\(transition.sourceIndex, privacy: .public) target=\(transition.targetIndex, privacy: .public) queue_depth=\(queueDepth, privacy: .public)"
    )

    let direction = transition.direction == .left ? ISSDirectionLeft : ISSDirectionRight
    guard iss_switch(direction) else {
      handleTransitionEffects(
        transitionCoordinator.injectionFailed(transitionID: transition.id)
      )
      return
    }
  }

  private func scheduleTimeout(for transitionID: UInt64) {
    transitionTimeoutWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.handleTransitionEffects(
        self.transitionCoordinator.timeout(transitionID: transitionID)
      )
    }
    transitionTimeoutWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + transitionTimeout,
      execute: workItem
    )
  }

  private func beginRecovery(for transitionID: UInt64) {
    recoveryWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.handleTransitionEffects(
        self.transitionCoordinator.finishRecovery(transitionID: transitionID)
      )
    }
    recoveryWorkItem = workItem
    DispatchQueue.main.asyncAfter(
      deadline: .now() + recoveryInterval,
      execute: workItem
    )
    transitionLogger.notice(
      "event=reconciliation id=\(transitionID, privacy: .public) status=waiting"
    )
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
        let effects = self.transitionCoordinator.receiveSpaceChange(self.loadSpaceSnapshot())
        self.handleTransitionEffects(effects)

        if !self.transitionCoordinator.isTransitionInFlight
          && !self.transitionCoordinator.isRecovering
        {
          if !effects.contains(where: { effect in
            if case .confirmed = effect { return true }
            if case .reconciled = effect { return true }
            return false
          }) {
            iss_reset_predictions()
            self.refreshSpaceInfo()
          }
          self.menuBarController.scheduleRefresh(after: 0.2)
        }
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
    performSpaceSwitchToIndex(index)
  }

  func menuBarControllerDidRequestRefresh(_ controller: MenuBarController) {
    guard !transitionCoordinator.isTransitionInFlight,
      !transitionCoordinator.isRecovering
    else {
      transitionLogger.debug("event=refresh_deferred reason=transition_active")
      return
    }
    refreshSpaceInfo()
  }
}
