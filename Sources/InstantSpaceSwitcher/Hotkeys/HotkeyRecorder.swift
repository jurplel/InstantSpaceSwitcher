import AppKit
import Carbon

@MainActor
final class HotkeyRecorder {
  static let shared = HotkeyRecorder()

  private var monitor: Any?
  private var completion: ((HotkeyCombination) -> Void)?
  private var cancellation: (() -> Void)?

  private init() {}

  func beginRecording(
    for identifier: HotkeyIdentifier,
    completion: @escaping (HotkeyCombination) -> Void,
    cancellation: @escaping () -> Void
  ) {
    endRecording()

    self.completion = completion
    self.cancellation = cancellation

    print("[HotkeyRecorder] Starting recording for \(identifier)")
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: handle(event:))
    print("[HotkeyRecorder] Local monitor installed: \(monitor != nil)")
    NSApp.activate(ignoringOtherApps: true)
    print("[HotkeyRecorder] App activated")
  }

  func endRecording() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    completion = nil
    cancellation = nil
  }

  private func handle(event: NSEvent) -> NSEvent? {
    print(
      "[HotkeyRecorder] Received event - keyCode: \(event.keyCode), modifiers: \(event.modifierFlags)"
    )

    guard let completion else {
      print("[HotkeyRecorder] No completion handler")
      return event
    }

    if event.keyCode == UInt16(kVK_Escape) {
      print("[HotkeyRecorder] Escape pressed - cancelling")
      cancellation?()
      endRecording()
      return nil
    }

    guard let combination = HotkeyCombination.from(event: event), combination.isValid else {
      print("[HotkeyRecorder] Invalid combination")
      NSSound.beep()
      return nil
    }

    print("[HotkeyRecorder] Valid combination: \(combination.displayString)")
    completion(combination)
    endRecording()
    return nil
  }
}
