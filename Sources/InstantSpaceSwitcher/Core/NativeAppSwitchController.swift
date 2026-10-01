import AppKit
import ApplicationServices
import ISS

@_silgen_name("_AXUIElementGetWindow")
private func windowID(_ element: AXUIElement, _ result: UnsafeMutablePointer<CGWindowID>) -> AXError

// App activation is observed after the native chooser commits its selection.
// No key is consumed, delayed, synthesized, or replayed by this controller.
@MainActor
final class NativeAppSwitchController {
  private let windowQueue = DispatchQueue(label: "app-switch-window", qos: .userInteractive)
  private var activationObserver: Any?
  private var settingsObserver: Any?
  private static weak var inputObserver: NativeAppSwitchController?
  private var permissionTimer: Timer?
  private var watchdog: Process?
  private var ownsSessionPreference = false
  private var generation = 0
  private var readyAt = 0.0
  private var lastInputAt = 0.0
  private var lastSwitchAt = 0.0
  private var spaceNavigationUntil = 0.0
  private var enabled = false

  // Dock owns the complete WindowServer workspace dictionary and replaces it
  // wholesale. A partial session dictionary drops Dock's other keys and breaks
  // the Mission Control layout, so change the native setting and let Dock
  // rebuild the dictionary. The original value is kept until it is restored.
  nonisolated private static let switchOnActivateKey = "AppleSpacesSwitchOnActivate" as CFString
  nonisolated private static let restoreKey = "appSwitchRestoreSwitchOnActivate"

  nonisolated private static func savedSwitchOnActivate() -> Bool? {
    _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    return CFPreferencesCopyValue(switchOnActivateKey,
      kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
  }

  nonisolated private static func setSwitchOnActivate(_ value: Bool?) {
    CFPreferencesSetValue(switchOnActivateKey, value as CFPropertyList?,
      kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    // Same notification System Settings posts; Dock rereads and resends.
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("com.apple.AppleSpacesSwitchOnActivate"), object: nil, userInfo: nil,
      deliverImmediately: true)
  }

  /// Restores the user's setting after a quit, crash, or interrupted session.
  @discardableResult
  nonisolated static func restoreSavedPreference() -> Bool {
    let defaults = UserDefaults.standard
    guard let original = defaults.string(forKey: restoreKey) else { return false }
    setSwitchOnActivate(original == "unset" ? nil : original == "true")
    defaults.removeObject(forKey: restoreKey)
    defaults.synchronize()
    return true
  }

  func setEnabled(_ enabled: Bool) {
    stop()
    self.enabled = enabled
    guard enabled else { return }
    let center = NSWorkspace.shared.notificationCenter
    activationObserver = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
      object: nil, queue: .main) { [weak self] notification in
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        MainActor.assumeIsolated { self?.activated(app) }
      }
    settingsObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.apple.AppleSpacesSwitchOnActivate"), object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.savedSettingChanged() }
    }
    // Observation only: distinguishes a fresh user selection from activation
    // notifications produced by the slide itself, including rapid Command-Tab.
    Self.inputObserver = self
    iss_set_user_input_callback { input in
      MainActor.assumeIsolated { NativeAppSwitchController.inputObserver?.observed(input) }
    }
    applySessionOverride()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if AXIsProcessTrusted() {
          if !self.ownsSessionPreference { self.applySessionOverride() }
        } else if self.ownsSessionPreference {
          self.restoreSessionPreference()
        }
      }
    }
  }

  func stop() {
    enabled = false
    generation += 1
    permissionTimer?.invalidate()
    permissionTimer = nil
    let center = NSWorkspace.shared.notificationCenter
    if let activationObserver { center.removeObserver(activationObserver) }
    if let settingsObserver { DistributedNotificationCenter.default().removeObserver(settingsObserver) }
    iss_set_user_input_callback(nil)
    Self.inputObserver = nil
    activationObserver = nil
    settingsObserver = nil
    restoreSessionPreference()
  }

  private func observed(_ input: ISSUserInput) {
    let now = ProcessInfo.processInfo.systemUptime
    if input == ISSUserInputSpaceNavigation {
      // Landing on another desktop may activate an app whose focused window
      // is elsewhere. Following that window would undo the user's swipe.
      spaceNavigationUntil = now + 1
      generation += 1
    } else {
      lastInputAt = now
      spaceNavigationUntil = 0
    }
  }

  private func restoreSessionPreference() {
    // Also restores a value left behind by a previous run.
    Self.restoreSavedPreference()
    ownsSessionPreference = false
    if let watchdog, watchdog.isRunning {
      watchdog.terminate()
      watchdog.waitUntilExit()
    }
    watchdog = nil
  }

  private func savedSettingChanged() {
    // Our own write reads back as false. True means the user turned the
    // native setting on in System Settings while the override was active.
    guard ownsSessionPreference, Self.savedSwitchOnActivate() != false else { return }
    UserDefaults.standard.set("true", forKey: Self.restoreKey)
    Self.setSwitchOnActivate(false)
  }

  private func applySessionOverride() {
    guard enabled, AXIsProcessTrusted() else { return }
    if watchdog == nil {
      guard let executable = Bundle.main.executableURL else { return }
      let process = Process()
      process.executableURL = executable
      process.arguments = ["--restore-app-switching-after-exit", String(ProcessInfo.processInfo.processIdentifier)]
      do { try process.run() } catch { return }
      watchdog = process
    }
    let defaults = UserDefaults.standard
    if defaults.string(forKey: Self.restoreKey) == nil {
      let original = Self.savedSwitchOnActivate()
      defaults.set(original.map { $0 ? "true" : "false" } ?? "unset", forKey: Self.restoreKey)
      defaults.synchronize()
    }
    Self.setSwitchOnActivate(false)
    ownsSessionPreference = true
    if ProcessInfo.processInfo.environment["ISS_APP_SWITCH_DIAGNOSTICS"] == "1" {
      print("Native app-switch override active; Accessibility trusted; native Space jump off until restore")
    }
    // Dock applies this asynchronously; no user input waits here.
    readyAt = ProcessInfo.processInfo.systemUptime + 0.5
  }

  private func activated(_ app: NSRunningApplication) {
    guard enabled, ownsSessionPreference, ProcessInfo.processInfo.systemUptime >= readyAt,
      app.activationPolicy == .regular else { return }
    let now = ProcessInfo.processInfo.systemUptime
    guard now >= spaceNavigationUntil else { return }
    if (iss_has_pending_switch() || now - lastSwitchAt < 0.4), lastInputAt <= lastSwitchAt { return }
    generation += 1
    let request = generation
    let pid = app.processIdentifier
    windowQueue.async { [weak self] in
      let window = Self.focusedWindow(pid: pid) ?? Self.frontWindow(pid: pid)
      DispatchQueue.main.async {
        guard let self, self.enabled, self.ownsSessionPreference, self.generation == request,
          app.isActive, let window else { return }
        self.lastSwitchAt = ProcessInfo.processInfo.systemUptime
        let success = iss_switch_to_window(window)
        if ProcessInfo.processInfo.environment["ISS_APP_SWITCH_DIAGNOSTICS"] == "1" {
          print("App switch pid=\(pid) window=\(window) posted=\(success) lookupMs=\(Int((self.lastSwitchAt - now) * 1000))")
        }
        if !success {
          // Release the override on failure so native switching remains usable.
          self.restoreSessionPreference()
        }
      }
    }
  }

  nonisolated private static func focusedWindow(pid: pid_t) -> CGWindowID? {
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(application, 0.04)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    var id: CGWindowID = 0
    guard windowID(value as! AXUIElement, &id) == .success, id != 0 else { return nil }
    return id
  }

  nonisolated private static func frontWindow(pid: pid_t) -> CGWindowID? {
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.first {
      $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0
    }?[kCGWindowNumber as String] as? CGWindowID
  }
}
