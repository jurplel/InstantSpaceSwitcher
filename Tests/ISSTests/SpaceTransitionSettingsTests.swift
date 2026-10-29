import XCTest
import ISS
@testable import InstantSpaceSwitcher

final class SpaceTransitionSettingsTests: XCTestCase {
    func testDurationMatchesExistingGestureSpeedPresets() {
        let presets: [(speed: Double, duration: TimeInterval)] = [
            (40.0, 0.35),
            (50.0, 0.25),
            (60.0, 0.18),
            (80.0, 0.10),
            (2000.0, 0.0)
        ]

        for preset in presets {
            XCTAssertEqual(
                SpaceTransitionSettings.duration(forGestureSpeed: preset.speed),
                preset.duration,
                "Unexpected duration for gesture speed \(preset.speed)"
            )
        }
    }

    func testUnknownGestureSpeedUsesInstantDuration() {
        XCTAssertEqual(SpaceTransitionSettings.duration(forGestureSpeed: 123.0), 0.0)
    }

    func testLeftDirectionMovesOutgoingSnapshotDownByDisplayHeight() {
        XCTAssertEqual(
            SpaceTransitionSettings.outgoingOffset(for: ISSDirectionLeft, height: 900),
            900
        )
    }

    func testRightDirectionMovesOutgoingSnapshotUpByDisplayHeight() {
        XCTAssertEqual(
            SpaceTransitionSettings.outgoingOffset(for: ISSDirectionRight, height: 900),
            -900
        )
    }
}
