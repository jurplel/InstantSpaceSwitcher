import XCTest
import ISS

// Unit tests for iss_is_expose_detected_in_window_list / iss_is_mission_control_detected_in_window_list.
// Access private C functions via @_silgen_name.

@_silgen_name("iss_is_expose_detected_in_window_list")
private func iss_is_expose_detected_in_window_list(_ windowList: CFArray) -> Bool

@_silgen_name("iss_is_mission_control_detected_in_window_list")
private func iss_is_mission_control_detected_in_window_list(_ windowList: CFArray) -> Bool
//
// Window structures are hardcoded from real probe output (expose_probe.c) captured
// on macOS Sequoia with two displays (1920x1080 primary, 1728x1117 secondary).
// No UI automation or Accessibility permission required.

final class OverlayDetectionTests: XCTestCase {

    // MARK: - Helpers

    /// Build a fake Dock window dictionary matching CGWindowListCopyWindowInfo output.
    private func dockWindow(layer: Int, x: Double, y: Double, width: Double, height: Double) -> NSDictionary {
        return [
            "kCGWindowOwnerName": "Dock",
            "kCGWindowLayer": NSNumber(value: layer),
            "kCGWindowBounds": [
                "X": NSNumber(value: x),
                "Y": NSNumber(value: y),
                "Width": NSNumber(value: width),
                "Height": NSNumber(value: height)
            ] as NSDictionary
        ]
    }

    /// Non-Dock window, should be ignored by both detectors.
    private func nonDockWindow(layer: Int) -> NSDictionary {
        return [
            "kCGWindowOwnerName": "WindowServer",
            "kCGWindowLayer": NSNumber(value: layer)
        ]
    }

    // MARK: - Normal state (probe ticks 1-4)
    // Only always-present Dock background windows at layer -2147483624.

    func testNormalStateNoOverlay() {
        let list: NSArray = [
            dockWindow(layer: -2147483624, x: -1728, y: 0,   width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0,     y: 0,   width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    // MARK: - App Exposé
    // Collected on macOS 26.2, dual-display (1920x1080 + 1728x1117).
    // Adds layer-18 overlays + 1-2 layer-20 windows.

    func testAppExposeDetected() {
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0,    y: 0,   width: 233,  height: 86),   // layer-20 #1
            dockWindow(layer: 20,  x: 0,    y: 0,   width: 1920, height: 1080), // layer-20 #2
            dockWindow(layer: 18,  x: 0,    y: 0,   width: 1920, height: 1080),
            dockWindow(layer: 18,  x: -1728, y: 0,  width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0,     y: 0, width: 1920, height: 1080),
        ]
        XCTAssertTrue(iss_is_expose_detected_in_window_list(list as CFArray),  "should detect App Exposé")
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray),     "should not report MC during App Exposé")
    }

    // MARK: - Mission Control (probe ticks 11-13)
    // Collected on macOS 26.2, dual-display (1920x1080 + 1728x1117).
    // Adds layer-18 overlays + 3+ layer-20 windows (3 on single-monitor, 4 on dual).

    func testMissionControlDetected() {
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0,    y: 0,  width: 1920, height: 1080), // layer-20 #1
            dockWindow(layer: 20,  x: 0,    y: 0,  width: 1920, height: 1080), // layer-20 #2
            dockWindow(layer: 20,  x: -1728, y: 0, width: 1728, height: 1117), // layer-20 #3
            dockWindow(layer: 18,  x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: 18,  x: 0,     y: 0, width: 1920, height: 1080),
            dockWindow(layer: -2147483624, x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0,     y: 0, width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray), "should not report Exposé during MC")
        XCTAssertTrue(iss_is_mission_control_detected_in_window_list(list as CFArray),      "should detect Mission Control")
    }

    // MARK: - Edge cases

    func testEmptyListReturnsFalse() {
        let list: NSArray = []
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testNonDockWindowsIgnored() {
        let list: NSArray = [
            nonDockWindow(layer: 18),
            nonDockWindow(layer: 20),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testLayer18OnlyNoSmallHUDIsNeither() {
        // Overlay present but insufficient layer-20 count → neither mode active
        let list: NSArray = [
            dockWindow(layer: 18, x: 0, y: 0, width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testSmallHUDWithoutLayer18IsNeither() {
        // HUD present but no layer-18 overlay → neither mode active
        let list: NSArray = [
            dockWindow(layer: 20, x: -981, y: 536, width: 233, height: 86),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    // MARK: - New probe data (count-based detection)
    // On some macOS builds, small HUD appears in BOTH modes.
    // Differentiate by layer-20 window count: Expose=1-2, MC=3+.

    func testAppExposeWithSmallHUD() {
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0,    y: 0,   width: 233,  height: 86),   // layer-20 #1 (small HUD)
            dockWindow(layer: 20,  x: 0,    y: 0,   width: 1920, height: 1080), // layer-20 #2
            dockWindow(layer: 18,  x: 0,    y: 0,   width: 1920, height: 1080),
            dockWindow(layer: 18,  x: -1728, y: 0,  width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0,     y: 0, width: 1920, height: 1080),
        ]
        XCTAssertTrue(iss_is_expose_detected_in_window_list(list as CFArray),  "should detect App Exposé")
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray),     "should not report MC during App Exposé")
    }

    func testMissionControlWithSmallHUD() {
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0,    y: 0,  width: 233,  height: 86),   // layer-20 #1 (small HUD)
            dockWindow(layer: 20,  x: 0,    y: 0,  width: 1920, height: 1080), // layer-20 #2
            dockWindow(layer: 20,  x: -1728, y: 0, width: 1728, height: 1117), // layer-20 #3
            dockWindow(layer: 18,  x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: 18,  x: 0,     y: 0, width: 1920, height: 1080),
            dockWindow(layer: -2147483624, x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0,     y: 0, width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray), "should not report Exposé during MC")
        XCTAssertTrue(iss_is_mission_control_detected_in_window_list(list as CFArray),      "should detect Mission Control")
    }

    // MARK: - Additional edge cases (boundary conditions)

    func testThreeLayer20WithLayer18IsMC() {
        // 3 layer-20 windows is the Mission Control threshold (single-monitor setup)
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // layer-20 #1
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // layer-20 #2
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // layer-20 #3
            dockWindow(layer: 18,  x: 0, y: 0, width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertTrue(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testFiveLayer20WithLayer18IsMC() {
        // 5+ layer-20 windows should still detect as Mission Control
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // #1
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // #2
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // #3
            dockWindow(layer: 20,  x: 0, y: 0, width: 1920, height: 1080), // #4
            dockWindow(layer: 20,  x: 0, y: 0, width: 1728, height: 1117), // #5
            dockWindow(layer: 18,  x: 0, y: 0, width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertTrue(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testLayer20WithoutLayer18IsNeither() {
        // Layer-20 windows without layer-18 overlay → neither mode
        let list: NSArray = [
            dockWindow(layer: 20, x: 0, y: 0, width: 1920, height: 1080),
            dockWindow(layer: 20, x: 0, y: 0, width: 1920, height: 1080),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testOneLayer20WithLayer18() {
        // 1 layer-20 + 2 layer-18 - Exposé variant (no small HUD)
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0,     y: 0, width: 1920, height: 1080),
            dockWindow(layer: 18,  x: 0,     y: 0, width: 1920, height: 1080),
            dockWindow(layer: 18,  x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: -1728, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0,     y: 0, width: 1920, height: 1080),
        ]
        XCTAssertTrue(iss_is_expose_detected_in_window_list(list as CFArray), "should detect Exposé")
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testSingleDisplayMissionControl() {
        // Single display (1728x1117) Mission Control with 2 layer-20 windows
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0, y: 0, width: 1728, height: 1117),
            dockWindow(layer: 20,  x: 0, y: 0, width: 1728, height: 1117),
            dockWindow(layer: 18,  x: 0, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0, y: 0, width: 1728, height: 1117),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertTrue(iss_is_mission_control_detected_in_window_list(list as CFArray), "should detect Mission Control on single display")
    }

    func testSingleDisplayNormalState() {
        // Single display (1728x1117) normal state with only wallpaper
        let list: NSArray = [
            dockWindow(layer: -2147483624, x: 0, y: 0, width: 1728, height: 1117),
        ]
        XCTAssertFalse(iss_is_expose_detected_in_window_list(list as CFArray))
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }

    func testSingleDisplayAppExpose() {
        // Single display (1728x1117) App Exposé with 1 layer-20 window
        let list: NSArray = [
            dockWindow(layer: 20,  x: 0, y: 0, width: 1728, height: 1117),
            dockWindow(layer: 18,  x: 0, y: 0, width: 1728, height: 1117),
            dockWindow(layer: -2147483624, x: 0, y: 0, width: 1728, height: 1117),
        ]
        XCTAssertTrue(iss_is_expose_detected_in_window_list(list as CFArray), "should detect App Exposé on single display")
        XCTAssertFalse(iss_is_mission_control_detected_in_window_list(list as CFArray))
    }
}
