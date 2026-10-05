import XCTest
import ISS

// Unit tests for iss_swipe_progress_for_phase.
// Access the non-exported C function via @_silgen_name (same approach as
// ExposeMcDetectTests). No events are posted; no permissions required.

// CGSGesturePhase is uint8_t in ISS.c; ISSDirection is a C enum (int).
@_silgen_name("iss_swipe_progress_for_phase")
private func iss_swipe_progress_for_phase(_ phase: UInt8, _ direction: ISSDirection) -> Double

private let phaseBegan: UInt8 = 1
private let phaseChanged: UInt8 = 2
private let phaseEnded: UInt8 = 4

final class SwipeProgressTests: XCTestCase {

  /// Began uses a small signed progress to minimize the visible transition.
  func testBeganUsesSmallSignedProgress() {
    XCTAssertEqual(iss_swipe_progress_for_phase(phaseBegan, ISSDirectionRight), 0.000016)
    XCTAssertEqual(iss_swipe_progress_for_phase(phaseBegan, ISSDirectionLeft), -0.000016)
  }

  /// Changed and Ended use the same small progress while retaining direction.
  func testChangedAndEndedUseSmallSignedProgress() {
    for phase in [phaseChanged, phaseEnded] {
      XCTAssertEqual(iss_swipe_progress_for_phase(phase, ISSDirectionRight), 0.000016)
      XCTAssertEqual(iss_swipe_progress_for_phase(phase, ISSDirectionLeft), -0.000016)
    }
  }

  /// All phases of one gesture must agree on direction.
  func testSignIsConsistentAcrossPhases() {
    for direction in [ISSDirectionLeft, ISSDirectionRight] {
      let signs = [phaseBegan, phaseChanged, phaseEnded].map {
        iss_swipe_progress_for_phase($0, direction).sign
      }
      XCTAssertEqual(Set(signs).count, 1, "phases disagree on direction for \(direction)")
    }
  }
}
