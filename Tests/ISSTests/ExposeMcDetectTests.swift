import XCTest
import ISS

// Unit tests for iss_is_expose_detected_in_window_list / iss_is_mission_control_detected_in_window_list.
// Access private C functions via @_silgen_name.

@_silgen_name("iss_is_expose_detected_in_window_list")
private func iss_is_expose_detected_in_window_list(_ windowList: CFArray) -> Bool

@_silgen_name("iss_is_mission_control_detected_in_window_list")
private func iss_is_mission_control_detected_in_window_list(_ windowList: CFArray) -> Bool

@_silgen_name("iss_normalize_gesture_velocity")
private func iss_normalize_gesture_velocity(_ velocity: Double) -> Double

@_silgen_name("iss_refresh_rate_normalization_scale")
private func iss_refresh_rate_normalization_scale(_ displayRefreshRate: Double, _ baselineRefreshRate: Double) -> Double

@_silgen_name("iss_normalize_gesture_velocity_for_refresh_rate")
private func iss_normalize_gesture_velocity_for_refresh_rate(
    _ velocity: Double,
    _ displayRefreshRate: Double,
    _ baselineRefreshRate: Double
) -> Double

@_silgen_name("iss_dock_swipe_velocity_for_phase")
private func iss_dock_swipe_velocity_for_phase(_ velocity: Double, _ phase: Int32) -> Double

@_silgen_name("iss_dock_swipe_velocity_for_phase_and_refresh_rate")
private func iss_dock_swipe_velocity_for_phase_and_refresh_rate(
    _ velocity: Double,
    _ phase: Int32,
    _ displayRefreshRate: Double,
    _ baselineRefreshRate: Double
) -> Double

@_silgen_name("iss_dock_swipe_progress_for_phase")
private func iss_dock_swipe_progress_for_phase(_ velocity: Double, _ phase: Int32) -> Double

@_silgen_name("iss_dock_swipe_progress_for_phase_and_refresh_rate")
private func iss_dock_swipe_progress_for_phase_and_refresh_rate(
    _ velocity: Double,
    _ phase: Int32,
    _ displayRefreshRate: Double,
    _ baselineRefreshRate: Double
) -> Double
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

final class GestureVelocityTests: XCTestCase {
    private let gesturePhaseBegan: Int32 = 1
    private let gesturePhaseChanged: Int32 = 2
    private let gesturePhaseEnded: Int32 = 4

    func testAllPresetsUseSharedActivationCurve() {
        let presets: [(input: Double, expected: Double)] = [
            (40.0, 40.0),
            (50.0, 46.25),
            (60.0, 56.0),
            (80.0, 86.0),
            (2000.0, 2000.0),
        ]

        for preset in presets {
            XCTAssertEqual(iss_normalize_gesture_velocity(preset.input), preset.expected, accuracy: 0.0001)
        }
    }

    func testNonInstantVelocityUsesFormulaInsteadOfPresetMapping() {
        XCTAssertEqual(iss_normalize_gesture_velocity(45.0), 42.6875, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity(70.0), 69.25, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity(125.0), 204.6875, accuracy: 0.0001)
    }

    func testRefreshNormalizationUsesBaselineRatio() {
        XCTAssertEqual(iss_refresh_rate_normalization_scale(120.0, 120.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(iss_refresh_rate_normalization_scale(240.0, 120.0), 2.0, accuracy: 0.0001)
        XCTAssertEqual(iss_refresh_rate_normalization_scale(180.0, 120.0), 1.5, accuracy: 0.0001)
    }

    func testUnknownRefreshRateUsesUnscaledVelocity() {
        XCTAssertEqual(iss_refresh_rate_normalization_scale(0.0, 120.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(iss_refresh_rate_normalization_scale(120.0, 0.0), 1.0, accuracy: 0.0001)
    }

    func testNonInstantVelocityScalesForHighRefreshDisplay() {
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(40.0, 240.0, 120.0), 40.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(50.0, 240.0, 120.0), 52.5, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(60.0, 240.0, 120.0), 72.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(80.0, 240.0, 120.0), 132.0, accuracy: 0.0001)
    }

    func testNonInstantVelocityScalesOffsetOnlyForLowRefreshDisplay() {
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(40.0, 60.0, 120.0), 40.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(50.0, 60.0, 120.0), 43.125, accuracy: 0.0001)
    }

    func testVelocityBelowPresetRangeUsesActivationFloor() {
        XCTAssertEqual(iss_normalize_gesture_velocity(1.0), 40.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity(39.0), 40.0, accuracy: 0.0001)
    }

    func testNonInstantVelocityNeverBecomesInstant() {
        XCTAssertEqual(iss_normalize_gesture_velocity(1999.0), 1999.0, accuracy: 0.0001)
        XCTAssertLessThan(iss_normalize_gesture_velocity(1999.0), 2000.0)
    }

    func testInstantAndHigherVelocityAreUnchanged() {
        XCTAssertEqual(iss_normalize_gesture_velocity(2000.0), 2000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity(4000.0), 4000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(2000.0, 240.0, 120.0), 2000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_normalize_gesture_velocity_for_refresh_rate(4000.0, 240.0, 120.0), 4000.0, accuracy: 0.0001)
    }

    func testPresetOrderIsPreserved() {
        let normalized = [40.0, 50.0, 60.0, 80.0, 2000.0].map(iss_normalize_gesture_velocity)

        for index in 1..<normalized.count {
            XCTAssertGreaterThan(normalized[index], normalized[index - 1])
        }
    }

    func testAllPhasesUseSameNormalizedVelocity() {
        let presets = [40.0, 50.0, 60.0, 80.0]

        for preset in presets {
            let expected = iss_normalize_gesture_velocity(preset)
            let began = iss_dock_swipe_velocity_for_phase(preset, gesturePhaseBegan)
            let changed = iss_dock_swipe_velocity_for_phase(preset, gesturePhaseChanged)
            let ended = iss_dock_swipe_velocity_for_phase(preset, gesturePhaseEnded)

            XCTAssertEqual(began, expected, accuracy: 0.0001)
            XCTAssertEqual(changed, expected, accuracy: 0.0001)
            XCTAssertEqual(ended, expected, accuracy: 0.0001)
        }
    }

    func testInstantPresetRemainsInstantForAllPhases() {
        XCTAssertEqual(iss_dock_swipe_velocity_for_phase(2000.0, gesturePhaseBegan), 2000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_velocity_for_phase(2000.0, gesturePhaseChanged), 2000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_velocity_for_phase(2000.0, gesturePhaseEnded), 2000.0, accuracy: 0.0001)
    }

    func testMultiSpaceVelocityAboveInstantIsNotReducedForAnyPhase() {
        XCTAssertEqual(iss_dock_swipe_velocity_for_phase(4000.0, gesturePhaseBegan), 4000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_velocity_for_phase(4000.0, gesturePhaseChanged), 4000.0, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_velocity_for_phase(4000.0, gesturePhaseEnded), 4000.0, accuracy: 0.0001)
    }

    func testBeganPhaseUsesMinimalProgress() {
        XCTAssertGreaterThan(iss_dock_swipe_progress_for_phase(100.0, gesturePhaseBegan), 0.0)
        XCTAssertLessThan(iss_dock_swipe_progress_for_phase(100.0, gesturePhaseBegan), 0.0001)
    }

    func testNormalPresetUsesMinimalProgress() {
        XCTAssertGreaterThan(iss_dock_swipe_progress_for_phase(40.0, gesturePhaseChanged), 0.0)
        XCTAssertLessThan(iss_dock_swipe_progress_for_phase(40.0, gesturePhaseChanged), 0.0001)
    }

    func testChangedAndEndedProgressIsConstantForFastNonInstantVelocity() {
        XCTAssertEqual(iss_dock_swipe_progress_for_phase(46.25, gesturePhaseChanged), 0.09, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_progress_for_phase(56.0, gesturePhaseEnded), 0.09, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_progress_for_phase(86.0, gesturePhaseChanged), 0.09, accuracy: 0.0001)
    }

    func testProgressDoesNotScaleWithRefreshRate() {
        XCTAssertEqual(
            iss_dock_swipe_progress_for_phase_and_refresh_rate(50.0, gesturePhaseChanged, 240.0, 120.0),
            0.09,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            iss_dock_swipe_progress_for_phase_and_refresh_rate(80.0, gesturePhaseEnded, 180.0, 120.0),
            0.09,
            accuracy: 0.0001
        )
        XCTAssertLessThan(
            iss_dock_swipe_progress_for_phase_and_refresh_rate(40.0, gesturePhaseChanged, 240.0, 120.0),
            0.0001
        )
    }

    func testProgressIsConstantForNonInstantVelocity() {
        XCTAssertEqual(iss_dock_swipe_progress_for_phase(1000.0, gesturePhaseChanged), 0.09, accuracy: 0.0001)
        XCTAssertEqual(iss_dock_swipe_progress_for_phase(1999.0, gesturePhaseEnded), 0.09, accuracy: 0.0001)
    }

    func testInstantAndMultiSpaceVelocityUseMinimalProgress() {
        XCTAssertLessThan(iss_dock_swipe_progress_for_phase(2000.0, gesturePhaseChanged), 0.0001)
        XCTAssertLessThan(iss_dock_swipe_progress_for_phase(4000.0, gesturePhaseEnded), 0.0001)
    }
}
