import CoreGraphics
import XCTest
import ISS

// Unit tests for the pure helpers behind carrying a dragged window across spaces
// (ISSWindowCarry.h). Frames, cursor positions and space IDs below are fake values
// chosen for each case; nothing touches the window server.

final class WindowCarryTests: XCTestCase {

  // MARK: - Drag detection

  private let tolerance = 8.0
  private let downFrame = CGRect(x: 100, y: 200, width: 600, height: 400)
  private let downCursor = CGPoint(x: 400, y: 210)  // on the fake window's title bar

  private func follows(windowBy dw: CGVector, cursorBy dc: CGVector, size: CGSize? = nil) -> Bool {
    let frame = CGRect(
      origin: CGPoint(x: downFrame.minX + dw.dx, y: downFrame.minY + dw.dy),
      size: size ?? downFrame.size)
    let cursor = CGPoint(x: downCursor.x + dc.dx, y: downCursor.y + dc.dy)
    return iss_window_follows_cursor(downFrame, downCursor, frame, cursor, tolerance)
  }

  /// A title-bar drag moves the window exactly with the cursor.
  func testWindowMovingWithCursorIsDragged() {
    XCTAssertTrue(follows(windowBy: CGVector(dx: 150, dy: -40), cursorBy: CGVector(dx: 150, dy: -40)))
  }

  /// Sampling lag between window and cursor is tolerated up to the tolerance.
  func testSmallLagWithinToleranceIsDragged() {
    XCTAssertTrue(follows(windowBy: CGVector(dx: 100, dy: 0), cursorBy: CGVector(dx: 108, dy: -8)))
    XCTAssertFalse(follows(windowBy: CGVector(dx: 100, dy: 0), cursorBy: CGVector(dx: 109, dy: 0)))
  }

  /// A held click or text selection: the cursor moves, the window does not.
  func testStationaryWindowIsNotDragged() {
    XCTAssertFalse(follows(windowBy: CGVector(dx: 0, dy: 0), cursorBy: CGVector(dx: 0, dy: 0)))
    XCTAssertFalse(follows(windowBy: CGVector(dx: 0, dy: 0), cursorBy: CGVector(dx: 200, dy: 30)))
  }

  /// Resizing from the left edge moves the origin with the cursor but changes the size.
  func testResizeIsNotDragged() {
    XCTAssertFalse(follows(
      windowBy: CGVector(dx: -50, dy: 0), cursorBy: CGVector(dx: -50, dy: 0),
      size: CGSize(width: 650, height: 400)))
  }

  /// A window moved by something else (e.g. a tiling tool) does not track the cursor.
  func testWindowMovingAwayFromCursorIsNotDragged() {
    XCTAssertFalse(follows(windowBy: CGVector(dx: 300, dy: 0), cursorBy: CGVector(dx: 20, dy: 0)))
  }

  // MARK: - Holding a title bar without moving

  private func held(windowBy dw: CGVector, cursorBy dc: CGVector, size: CGSize? = nil) -> Bool {
    let frame = CGRect(
      origin: CGPoint(x: downFrame.minX + dw.dx, y: downFrame.minY + dw.dy),
      size: size ?? downFrame.size)
    let cursor = CGPoint(x: downCursor.x + dc.dx, y: downCursor.y + dc.dy)
    return iss_window_is_held(downFrame, downCursor, frame, cursor, 4)
  }

  /// Pressing and holding without moving, allowing a little cursor jitter.
  func testStillPressIsHeld() {
    XCTAssertTrue(held(windowBy: CGVector(dx: 0, dy: 0), cursorBy: CGVector(dx: 0, dy: 0)))
    XCTAssertTrue(held(windowBy: CGVector(dx: 0, dy: 0), cursorBy: CGVector(dx: 4, dy: -4)))
  }

  /// Once the cursor or the window moves, it is a drag (or a selection), not a hold.
  func testMovementEndsHold() {
    XCTAssertFalse(held(windowBy: CGVector(dx: 0, dy: 0), cursorBy: CGVector(dx: 5, dy: 0)))
    XCTAssertFalse(held(windowBy: CGVector(dx: 20, dy: 0), cursorBy: CGVector(dx: 20, dy: 0)))
    XCTAssertFalse(held(windowBy: CGVector(dx: 0, dy: 0), cursorBy: CGVector(dx: 0, dy: 0),
                        size: CGSize(width: 610, height: 400)))
  }

  /// Accessibility roles that grab the window when pressed: frame, toolbar, title text.
  func testDragAreaRoles() {
    XCTAssertTrue(iss_ax_role_is_drag_area("AXWindow", nil))
    XCTAssertTrue(iss_ax_role_is_drag_area("AXToolbar", "AXWindow"))
    XCTAssertTrue(iss_ax_role_is_drag_area("AXStaticText", "AXWindow"))
  }

  /// Content, controls and nested text never grab the window.
  func testNonDragAreaRoles() {
    XCTAssertFalse(iss_ax_role_is_drag_area("AXTextArea", "AXScrollArea"))
    XCTAssertFalse(iss_ax_role_is_drag_area("AXButton", "AXToolbar"))
    XCTAssertFalse(iss_ax_role_is_drag_area("AXStaticText", "AXGroup"))
    XCTAssertFalse(iss_ax_role_is_drag_area("AXStaticText", nil))
    XCTAssertFalse(iss_ax_role_is_drag_area(nil, "AXWindow"))
  }

  // MARK: - Routing

  func testCarryOnlyWhenAvailableDraggedAndCarriable() {
    XCTAssertEqual(iss_choose_switch_route(true, true, true), ISSSwitchRouteCarry)
    XCTAssertEqual(iss_choose_switch_route(false, true, true), ISSSwitchRouteSwipe)
    XCTAssertEqual(iss_choose_switch_route(true, false, true), ISSSwitchRouteSwipe)
    XCTAssertEqual(iss_choose_switch_route(true, true, false), ISSSwitchRouteSwipe)
    XCTAssertEqual(iss_choose_switch_route(false, false, false), ISSSwitchRouteSwipe)
  }

  // MARK: - Eligibility (fake space IDs; CGS type 0 = user space, 4 = fullscreen)

  private let userType: Int32 = 0
  private let fullscreenType: Int32 = 4

  func testWindowOnCurrentUserSpaceCanBeCarried() {
    XCTAssertTrue(iss_window_can_be_carried(1, 7, 7, userType, userType))
  }

  func testStickyWindowIsRefused() {
    XCTAssertFalse(iss_window_can_be_carried(8, 7, 7, userType, userType))
  }

  func testWindowNotOnCurrentSpaceIsRefused() {
    XCTAssertFalse(iss_window_can_be_carried(1, 3, 7, userType, userType))
    XCTAssertFalse(iss_window_can_be_carried(0, 0, 7, userType, userType))
  }

  func testFullscreenSourceOrTargetIsRefused() {
    XCTAssertFalse(iss_window_can_be_carried(1, 7, 7, fullscreenType, userType))
    XCTAssertFalse(iss_window_can_be_carried(1, 7, 7, userType, fullscreenType))
  }

  // MARK: - Target resolution

  private func directionTarget(_ current: UInt32, _ count: UInt32, _ direction: ISSDirection) -> UInt32? {
    var target: UInt32 = 0
    return iss_target_index_for_direction(current, count, direction, &target) ? target : nil
  }

  func testDirectionalTargets() {
    XCTAssertEqual(directionTarget(2, 8, ISSDirectionRight), 3)
    XCTAssertEqual(directionTarget(2, 8, ISSDirectionLeft), 1)
  }

  func testDirectionalEdgesAreBlocked() {
    XCTAssertNil(directionTarget(0, 8, ISSDirectionLeft))
    XCTAssertNil(directionTarget(7, 8, ISSDirectionRight))
    XCTAssertEqual(directionTarget(0, 8, ISSDirectionRight), 1)
    XCTAssertEqual(directionTarget(7, 8, ISSDirectionLeft), 6)
  }

  func testSingleOrInvalidSpaceListIsBlocked() {
    XCTAssertNil(directionTarget(0, 1, ISSDirectionLeft))
    XCTAssertNil(directionTarget(0, 1, ISSDirectionRight))
    XCTAssertNil(directionTarget(0, 0, ISSDirectionRight))
    XCTAssertNil(directionTarget(9, 8, ISSDirectionLeft))
  }

  /// Index switches (Cmd+N, last space) clamp to the last space like iss_switch_to_index.
  func testIndexTargetsClampToLastSpace() {
    XCTAssertEqual(iss_clamp_space_index(0, 8), 0)
    XCTAssertEqual(iss_clamp_space_index(4, 8), 4)
    XCTAssertEqual(iss_clamp_space_index(7, 8), 7)
    XCTAssertEqual(iss_clamp_space_index(8, 8), 7)
    XCTAssertEqual(iss_clamp_space_index(15, 8), 7)
  }

  // MARK: - Runtime signature checks (encodings observed on macOS 27.0.1)

  func testEncodingMatchesIgnoringOffsets() {
    XCTAssertTrue(iss_objc_encoding_matches("@32@0:8@16Q24", "@@:@Q"))  // initWithWindows:spaceID:
    XCTAssertTrue(iss_objc_encoding_matches("@24@0:8@16", "@@:@"))  // initWithSpaces:
    XCTAssertTrue(iss_objc_encoding_matches("v16@0:8", "v@:"))  // performWithWMBridgeDelegate
  }

  func testEncodingMismatchesAreRejected() {
    XCTAssertFalse(iss_objc_encoding_matches("@32@0:8@16I24", "@@:@Q"))  // wrong argument type
    XCTAssertFalse(iss_objc_encoding_matches("@24@0:8@16", "@@:@Q"))  // missing argument
    XCTAssertFalse(iss_objc_encoding_matches("@32@0:8@16Q24", "@@:@"))  // extra argument
    XCTAssertFalse(iss_objc_encoding_matches("v24@0:8@16", "v@:"))  // perform takes an argument
    XCTAssertFalse(iss_objc_encoding_matches("@32@0:8r*16Q24", "@@:@Q"))  // qualifiers never match
    XCTAssertFalse(iss_objc_encoding_matches(nil, "v@:"))
    XCTAssertFalse(iss_objc_encoding_matches("", "v@:"))
  }
}
