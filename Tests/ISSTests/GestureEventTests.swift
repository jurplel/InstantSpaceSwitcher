import CoreGraphics
import ISSInternalTestSupport
import XCTest

final class GestureEventTests: XCTestCase {
    private func field(_ value: UInt32) -> CGEventField {
        CGEventField(rawValue: value)!
    }

    func testLegacyConstructionPreservesGestureFields() throws {
        for phase: UInt8 in [1, 2, 4] {
            for sign in [-1.0, 1.0] {
                let event = try XCTUnwrap(iss_create_dock_swipe_event(
                    phase, sign * Double(Float.leastNonzeroMagnitude), sign * 2000, false))
                    .takeRetainedValue()
                XCTAssertEqual(event.getIntegerValueField(field(55)), 30)
                XCTAssertEqual(event.getIntegerValueField(field(110)), 23)
                XCTAssertEqual(event.getIntegerValueField(field(132)), Int64(phase))
                XCTAssertEqual(event.getIntegerValueField(field(123)), 1)
                XCTAssertEqual(event.getDoubleValueField(field(124)),
                               sign * Double(Float.leastNonzeroMagnitude))
                XCTAssertEqual(event.getDoubleValueField(field(129)), sign * 2000)
                XCTAssertEqual(event.getDoubleValueField(field(130)), sign * 2000)
            }
        }
    }

    func testModernConstructionSurvivesSerialization() throws {
        for phase: UInt8 in [1, 2, 4] {
            for sign in [-1.0, 1.0] {
                let event = try XCTUnwrap(iss_create_dock_swipe_event(
                    phase, sign / 65536, sign * 2000, true)).takeRetainedValue()
                XCTAssertEqual(event.getIntegerValueField(field(55)), 30)
                XCTAssertEqual(event.getIntegerValueField(field(132)), Int64(phase))
                XCTAssertEqual(event.getDoubleValueField(field(124)), sign / 65536)
                XCTAssertEqual(event.getDoubleValueField(field(129)), phase == 4 ? sign * 2000 : 0)
                XCTAssertEqual(event.getDoubleValueField(field(130)), 0)
            }
        }
    }
}
