import CoreGraphics
import ISS
import XCTest

@_silgen_name("iss_start_switch_animation")
private func startAnimation(
  _ direction: ISSDirection, _ speed: Double,
  _ post: @convention(c) (CGEvent) -> Void
) -> Bool

private struct SwipeSample {
  let phase: Int64
  let progress: Double
  let velocity: Double
  let time: TimeInterval
}

private var samples: [SwipeSample] = []
private let captureSwipe: @convention(c) (CGEvent) -> Void = { event in
  samples.append(SwipeSample(
    phase: event.getIntegerValueField(CGEventField(rawValue: 132)!),
    progress: event.getDoubleValueField(CGEventField(rawValue: 124)!),
    velocity: event.getDoubleValueField(CGEventField(rawValue: 129)!),
    time: ProcessInfo.processInfo.systemUptime
  ))
}

final class GestureAnimationTests: XCTestCase {
  override func setUp() {
    XCTAssertTrue(Thread.isMainThread)
    iss_destroy()
    iss_set_animation_duration(0)
    iss_set_animation_curve(0.1, 0.1)
    samples = []
  }

  override func tearDown() {
    iss_destroy()
    samples = []
  }

  func testFastSlideIsAsynchronousAndReachesDestinationBeforeRelease() {
    XCTAssertTrue(startAnimation(ISSDirectionRight, 50, captureSwipe))
    XCTAssertEqual(samples.map(\.phase), [1], "Starting a slide must not block the UI")
    iss_wait_for_pending_switch()

    XCTAssertEqual(samples.last?.phase, 4)
    XCTAssertEqual(samples.last?.progress, 2)
    XCTAssertEqual(samples.last?.velocity, 0, "A normal finish must not inject a velocity spike")
    XCTAssertEqual(samples[samples.count - 2].phase, 2)
    XCTAssertEqual(samples[samples.count - 2].progress, 2)
    XCTAssertGreaterThan(samples.last!.time - samples[samples.count - 2].time, 0.003,
                         "Dock needs time to consume the last progress update before release")
    let changes = samples.filter { $0.phase == 2 }
    XCTAssertGreaterThan(changes.count, 3)
    for (before, after) in zip(changes, changes.dropFirst()) {
      XCTAssertGreaterThanOrEqual(after.progress, before.progress)
      XCTAssertLessThanOrEqual(after.progress, 2)
    }
    let duration = samples.last!.time - samples.first!.time
    XCTAssertGreaterThanOrEqual(duration, 0.21)
    XCTAssertLessThan(duration, 0.5, "The gesture must not retain the one-second tail")
    let motionDuration = samples[samples.count - 2].time - samples.first!.time
    let middle = changes.filter { $0.progress / 2 >= 0.15 && $0.progress / 2 <= 0.85 }
    XCTAssertGreaterThan(middle.count, 2)
    for sample in middle {
      let t = (sample.time - samples.first!.time) / motionDuration
      XCTAssertEqual(sample.progress / 2, t, accuracy: 0.06, "Middle should stay close to linear")
    }
  }

  func testReverseRequestFinishesOldGestureBeforeBeginningNewOne() {
    XCTAssertTrue(startAnimation(ISSDirectionRight, 50, captureSwipe))
    XCTAssertTrue(startAnimation(ISSDirectionLeft, 80, captureSwipe))
    XCTAssertEqual(samples.map(\.phase), [1, 2, 4, 1])
    XCTAssertEqual(samples[2].progress, 2)
    XCTAssertEqual(samples[2].velocity, 2000, "Interruption should finish the old gesture immediately")
    iss_wait_for_pending_switch()
    XCTAssertEqual(samples.last?.progress, -2)
    XCTAssertEqual(samples.last?.velocity, 0)
    XCTAssertTrue(samples.dropFirst(3).allSatisfy { $0.progress <= 0 })
  }

  func testInstantKeepsOriginalThreeEventSequence() {
    XCTAssertTrue(startAnimation(ISSDirectionLeft, 2000, captureSwipe))
    XCTAssertEqual(samples.map(\.phase), [1, 2, 4])
    XCTAssertTrue(samples.allSatisfy { abs($0.progress) < 1e-30 && $0.velocity == -2000 })
    iss_wait_for_pending_switch()
    XCTAssertEqual(samples.count, 3)
  }

  func testShutdownClosesGestureAndRemovesTimer() {
    XCTAssertTrue(startAnimation(ISSDirectionRight, 50, captureSwipe))
    iss_destroy()
    XCTAssertEqual(samples.map(\.phase), [1, 2, 4])
    CFRunLoopRunInMode(.defaultMode, 0.04, false)
    XCTAssertEqual(samples.count, 3)
  }

  func testInvalidSpeedDoesNotInterruptPendingGesture() {
    XCTAssertTrue(startAnimation(ISSDirectionRight, 50, captureSwipe))
    for speed in [0, -1, Double.nan, Double.infinity] {
      XCTAssertFalse(startAnimation(ISSDirectionLeft, speed, captureSwipe))
    }
    XCTAssertEqual(samples.map(\.phase), [1])
    iss_wait_for_pending_switch()
    XCTAssertEqual(samples.last?.progress, 2)
  }

  func testCurveShapesStayMonotonicAndAlwaysComplete() {
    for start in [0.0, 0.1, 0.25, 0.5] {
      for end in [0.0, 0.1, 0.25, 0.5] {
        XCTAssertEqual(iss_animation_progress(0, start, end), 0, accuracy: 1e-12)
        XCTAssertEqual(iss_animation_progress(1, start, end), 1, accuracy: 1e-12)
        var previous = 0.0
        for i in 0...100 {
          let p = iss_animation_progress(Double(i) / 100, start, end)
          XCTAssertGreaterThanOrEqual(p, previous)
          XCTAssertLessThanOrEqual(p, 1)
          previous = p
        }
      }
    }
    XCTAssertEqual(iss_animation_progress(0.37, 0, 0), 0.37, accuracy: 1e-12)
    XCTAssertLessThan(iss_animation_progress(0.5, 0.5, 0), 0.5)
    XCTAssertGreaterThan(iss_animation_progress(0.5, 0, 0.5), 0.5)
  }

  func testSettingsChangesAffectNextSlideWithoutWarpingActiveSlide() {
    iss_set_animation_duration(0.12)
    iss_set_animation_curve(0, 0)
    XCTAssertTrue(startAnimation(ISSDirectionRight, 50, captureSwipe))
    iss_set_animation_duration(0.8)
    iss_set_animation_curve(0.5, 0)
    iss_wait_for_pending_switch()
    let movementDuration = samples[samples.count - 2].time - samples.first!.time
    XCTAssertGreaterThanOrEqual(movementDuration, 0.12)
    XCTAssertLessThan(movementDuration, 0.3)
    for sample in samples where sample.phase == 2 && sample.progress < 1.8 {
      XCTAssertEqual(sample.progress / 2, (sample.time - samples.first!.time) / 0.12, accuracy: 0.02)
    }
    samples = []
    XCTAssertTrue(startAnimation(ISSDirectionRight, 2000, captureSwipe))
    XCTAssertEqual(samples.map(\.phase), [1, 2, 4], "Instant ignores custom duration and curve")
  }
}
