import CoreFoundation
import ISS
import XCTest

@_silgen_name("iss_resolve_window_space")
private func resolveWindowSpace(_ displays: CFArray, _ memberships: CFArray,
                                _ info: UnsafeMutablePointer<ISSSpaceInfo>,
                                _ target: UnsafeMutablePointer<UInt32>) -> Bool

final class WindowSpaceTests: XCTestCase {
  private func display(_ name: String, active: Int, spaces: [Int]) -> [String: Any] {
    ["Display Identifier": name, "Current Space": ["id64": active],
     "Spaces": spaces.map { ["id64": $0] }]
  }

  func testFindsDestinationOnSecondDisplayIncludingFullscreenSpace() {
    let displays = [display("left", active: 1, spaces: [1, 2]),
                    display("right", active: 3, spaces: [3, 4, 5])]
    var info = ISSSpaceInfo()
    var target: UInt32 = 99
    XCTAssertTrue(resolveWindowSpace(displays as CFArray, [5] as CFArray, &info, &target))
    XCTAssertEqual(info.currentIndex, 0)
    XCTAssertEqual(info.spaceCount, 3)
    XCTAssertEqual(target, 2)
    let identifier = withUnsafePointer(to: info.displayID) {
      $0.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
    }
    XCTAssertEqual(identifier, "right")
  }

  func testAllDesktopWindowPrefersAlreadyVisibleMembership() {
    let displays = [display("left", active: 2, spaces: [1, 2, 3])]
    var info = ISSSpaceInfo()
    var target: UInt32 = 99
    XCTAssertTrue(resolveWindowSpace(displays as CFArray, [1, 2, 3] as CFArray, &info, &target))
    XCTAssertEqual(target, info.currentIndex)
    XCTAssertEqual(target, 1)
  }

  func testAlreadyVisibleOnAnotherDisplayDoesNotSwitchFirstDisplay() {
    let displays = [display("left", active: 1, spaces: [1, 2]),
                    display("right", active: 3, spaces: [3, 4])]
    var info = ISSSpaceInfo()
    var target: UInt32 = 99
    XCTAssertTrue(resolveWindowSpace(displays as CFArray, [2, 3] as CFArray, &info, &target))
    XCTAssertEqual(target, info.currentIndex)
  }

  func testUnknownMembershipAndMissingCurrentSpaceFailSafely() {
    var info = ISSSpaceInfo()
    var target: UInt32 = 99
    XCTAssertFalse(resolveWindowSpace([display("left", active: 1, spaces: [1, 2])] as CFArray,
                                     [999] as CFArray, &info, &target))
    let malformed: [[String: Any]] = [["Display Identifier": "left", "Spaces": [["id64": 1]]]]
    XCTAssertFalse(resolveWindowSpace(malformed as CFArray, [1] as CFArray, &info, &target))
    XCTAssertEqual(target, 99)
  }
}
