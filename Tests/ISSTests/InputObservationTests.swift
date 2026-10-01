import CoreGraphics
import ISS
import XCTest

@_silgen_name("iss_observe_user_input")
private func observeInput(_ type: CGEventType, _ event: CGEvent)

private var observedInputs: [ISSUserInput] = []

final class InputObservationTests: XCTestCase {
  override func setUp() {
    observedInputs = []
    iss_set_swipe_override(false)
    iss_set_user_input_callback { observedInputs.append($0) }
  }

  override func tearDown() {
    iss_set_user_input_callback(nil)
  }

  private func swipe(phase: Int64, sourcePID: Int64 = 0, horizontal: Bool = true) -> CGEvent {
    let event = CGEvent(source: nil)!
    event.setIntegerValueField(.eventSourceUnixProcessID, value: sourcePID)
    for (field, value) in [(55, Int64(30)), (110, Int64(23)),
                           (123, horizontal ? Int64(1) : Int64(2)), (132, phase)] {
      event.setIntegerValueField(CGEventField(rawValue: UInt32(field))!, value: value)
    }
    return event
  }

  func testPhysicalSwipeIsObservedEvenWhenSwipeOverrideIsOff() {
    for phase: Int64 in [1, 2, 4, 8] {
      let event = swipe(phase: phase)
      observeInput(CGEventType(rawValue: 30)!, event)
      XCTAssertEqual(event.getIntegerValueField(CGEventField(rawValue: 132)!), phase)
    }
    XCTAssertEqual(observedInputs, Array(repeating: ISSUserInputSpaceNavigation, count: 4))
  }

  func testOurSyntheticSwipeAndVerticalGesturesCannotSuppressAppSwitching() {
    observeInput(CGEventType(rawValue: 30)!, swipe(phase: 1, sourcePID: 1234))
    observeInput(CGEventType(rawValue: 30)!, swipe(phase: 1, horizontal: false))
    XCTAssertTrue(observedInputs.isEmpty)
  }

  func testCommandTabAndControlArrowAreObservedWithoutChangingKeys() {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
    event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
    event.flags = .maskCommand
    observeInput(.keyDown, event)
    XCTAssertEqual(observedInputs, [ISSUserInputCommandTab])
    XCTAssertEqual(event.flags, .maskCommand)
    XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 48)
    observeInput(.keyUp, event)
    XCTAssertEqual(observedInputs.count, 1)
    event.setIntegerValueField(.keyboardEventKeycode, value: 124)
    event.flags = .maskControl
    observeInput(.keyDown, event)
    XCTAssertEqual(observedInputs.last, ISSUserInputSpaceNavigation)
    event.setIntegerValueField(.keyboardEventKeycode, value: 0)
    event.flags = []
    observeInput(.keyDown, event)
    XCTAssertEqual(observedInputs.count, 2)
  }
}
