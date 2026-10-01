import AppKit

@main
class InstantSpaceSwitcherApp {
  static func main() {
    if ProcessInfo.processInfo.environment["ISS_APP_SWITCH_DIAGNOSTICS"] == "1" { setbuf(stdout, nil) }
    // A separate process restores the runtime preference even after a crash.
    // It has no UI, event monitor, or Accessibility access; it only restores the
    // native setting recorded before the override.
    if CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--restore-app-switching-after-exit",
      let parent = Int32(CommandLine.arguments[2]), parent > 1 {
      while kill(parent, 0) == 0 { usleep(250_000) }
      NativeAppSwitchController.restoreSavedPreference()
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }
}
