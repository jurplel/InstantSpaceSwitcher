import CoreGraphics
import XCTest

@_silgen_name("iss_requires_event_augmentation_for_version")
private func iss_requires_event_augmentation_for_version(_ version: UnsafePointer<CChar>) -> Bool

@_silgen_name("iss_create_macos27_dock_swipe_event_data_for_testing")
private func iss_create_macos27_dock_swipe_event_data_for_testing(
  _ phase: Int32, _ direction: Int32
) -> Unmanaged<CFData>?

@_silgen_name("iss_direction_from_hardware_swipe")
private func iss_direction_from_hardware_swipe(_ value: Double) -> Int32

final class MacOS27GestureEventTests: XCTestCase {
  func testEventAugmentationStartsAtMacOS27() {
    XCTAssertFalse(iss_requires_event_augmentation_for_version("26.6"))
    XCTAssertTrue(iss_requires_event_augmentation_for_version("27.0"))
    XCTAssertTrue(iss_requires_event_augmentation_for_version("28.0"))
    XCTAssertFalse(iss_requires_event_augmentation_for_version("invalid"))
  }

  func testHardwareSwipeDirectionMatchesPhysicalDirectionOnMacOS27() {
    XCTAssertEqual(iss_direction_from_hardware_swipe(-0.1), 0)
    XCTAssertEqual(iss_direction_from_hardware_swipe(0.1), 1)
  }

  func testAugmentedDockSwipeCarriesRawIOHIDPayloadForEveryPhase() throws {
    for phase: Int32 in [1, 2, 4] {
      let data = try XCTUnwrap(
        iss_create_macos27_dock_swipe_event_data_for_testing(phase, 1)?.takeRetainedValue())
      let bytes = Array(
        UnsafeBufferPointer(
          start: try XCTUnwrap(CFDataGetBytePtr(data)), count: CFDataGetLength(data)))

      XCTAssertGreaterThan(bytes.count, 100)
      XCTAssertTrue(
        zip(bytes, bytes.dropFirst()).contains { $0 == 0x10 && $1 == 0x6D },
        "phase \(phase) must include serialized CGEvent field 4205")
    }
  }
}
