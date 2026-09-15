import XCTest
import ISS

@_silgen_name("iss_should_override_hardware_dock_swipe")
private func iss_should_override_hardware_dock_swipe(
  _ exposeActive: Bool, _ missionControlActive: Bool
) -> Bool

final class SwipeRoutingTests: XCTestCase {
  func testNormalDesktopUsesInstantOverride() {
    XCTAssertTrue(iss_should_override_hardware_dock_swipe(false, false))
  }

  func testMissionControlUsesNativeGesture() {
    XCTAssertFalse(iss_should_override_hardware_dock_swipe(false, true))
  }

  func testAppExposeUsesNativeGesture() {
    XCTAssertFalse(iss_should_override_hardware_dock_swipe(true, false))
  }
}
