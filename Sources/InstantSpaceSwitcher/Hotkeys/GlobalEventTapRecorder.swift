import AppKit
import Carbon

final class GlobalEventTapRecorder {
  static let shared = GlobalEventTapRecorder()

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var onKeyPress: ((NSEvent) -> Void)?
  private var onMouseClick: (() -> Void)?

  private init() {}

  func startRecording(onKeyPress: @escaping (NSEvent) -> Void, onMouseClick: @escaping () -> Void) {
    stopRecording()

    self.onKeyPress = onKeyPress
    self.onMouseClick = onMouseClick

    let eventMask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { _, type, event, userInfo in
          guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
          let recorder = Unmanaged<GlobalEventTapRecorder>.fromOpaque(userInfo)
            .takeUnretainedValue()

          // Handle mouse clicks - cancel recording
          if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            recorder.onMouseClick?()
            return nil  // Consume the click
          }

          // Handle key presses
          if let nsEvent = NSEvent(cgEvent: event) {
            recorder.onKeyPress?(nsEvent)
          }

          // Consume the event so it doesn't propagate
          return nil
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      return
    }

    self.eventTap = eventTap

    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  func stopRecording() {
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
    }

    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }

    onKeyPress = nil
    onMouseClick = nil
  }
}
