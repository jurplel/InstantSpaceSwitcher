import AppKit
import CoreGraphics
import ISS
import XCTest
@testable import InstantSpaceSwitcher

@MainActor
final class SpaceTransitionOverlayTests: XCTestCase {
  func testSuccessfulTransitionCapturesShowsSwitchesCapturesAndAnimates() async throws {
    let events = EventLog()
    let capture = FakeCaptureProvider(events: events, results: [.image, .image])
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)

    let didSwitch = await transition.transition(
      direction: ISSDirectionRight,
      duration: 0.18,
      canSwitch: { events.append("canSwitch"); return true },
      switchSpace: {
        events.append("switch")
        NSWorkspace.shared.notificationCenter.post(
          name: NSWorkspace.activeSpaceDidChangeNotification,
          object: nil
        )
        return true
      }
    )

    XCTAssertTrue(didSwitch)
    XCTAssertEqual(capture.captureCount, 2)
    XCTAssertEqual(capture.excludedWindows, [nil, 42])
    XCTAssertEqual(presenter.showCount, 1)
    XCTAssertEqual(presenter.animationCount, 1)
    XCTAssertEqual(presenter.removeCount, 1)
    XCTAssertEqual(events.values, ["canSwitch", "capture", "show", "switch", "capture", "animate", "remove"])
    XCTAssertNil(transition.lastCaptureError)
  }

  func testCanSwitchFalseDoesNotCaptureShowOrSwitch() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(events: events, results: [.image])
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)

    let didSwitch = await transition.transition(
      direction: ISSDirectionLeft,
      duration: 0.25,
      canSwitch: { false },
      switchSpace: { events.append("switch"); return true }
    )

    XCTAssertFalse(didSwitch)
    XCTAssertEqual(capture.captureCount, 0)
    XCTAssertEqual(presenter.showCount, 0)
    XCTAssertEqual(presenter.removeCount, 0)
    XCTAssertFalse(events.values.contains("switch"))
  }

  func testDeniedScreenRecordingPermissionIsDistinguishableAndFallsBackToSwitch() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(
      events: events,
      results: [.failure(SpaceTransitionCaptureError.screenRecordingPermissionDenied)]
    )
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)
    var switchCount = 0

    let didSwitch = await transition.transition(
      direction: ISSDirectionRight,
      duration: 0.18,
      canSwitch: { true },
      switchSpace: { switchCount += 1; return true }
    )

    XCTAssertTrue(didSwitch)
    XCTAssertEqual(switchCount, 1)
    XCTAssertEqual(transition.lastCaptureError, .screenRecordingPermissionDenied)
    XCTAssertNotNil(SpaceTransitionCaptureError.screenRecordingSettingsURL)
    XCTAssertEqual(presenter.showCount, 0)
    XCTAssertEqual(presenter.removeCount, 0)
  }

  func testOutgoingCaptureFailureSwitchesWithoutOverlay() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(events: events, results: [.failure(.captureFailed)])
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)
    var switchCount = 0

    let didSwitch = await transition.transition(
      direction: ISSDirectionLeft,
      duration: 0.25,
      canSwitch: { true },
      switchSpace: { switchCount += 1; return true }
    )

    XCTAssertTrue(didSwitch)
    XCTAssertEqual(switchCount, 1)
    XCTAssertEqual(capture.captureCount, 1)
    XCTAssertEqual(transition.lastCaptureError, .captureFailed)
    XCTAssertEqual(presenter.showCount, 0)
    XCTAssertEqual(presenter.removeCount, 0)
  }

  func testDestinationCaptureFailureKeepsSwitchAndRemovesOverlay() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(
      events: events,
      results: [.image, .failure(.captureFailed)]
    )
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)
    var switchCount = 0

    let didSwitch = await transition.transition(
      direction: ISSDirectionLeft,
      duration: 0.25,
      canSwitch: {
        true
      },
      switchSpace: {
        switchCount += 1
        NSWorkspace.shared.notificationCenter.post(
          name: NSWorkspace.activeSpaceDidChangeNotification,
          object: nil
        )
        return true
      }
    )

    XCTAssertTrue(didSwitch)
    XCTAssertEqual(switchCount, 1)
    XCTAssertEqual(capture.captureCount, 2)
    XCTAssertEqual(transition.lastCaptureError, .captureFailed)
    XCTAssertEqual(presenter.animationCount, 0)
    XCTAssertEqual(presenter.removeCount, 1)
  }

  func testMissingSpaceChangeNotificationRemovesOverlayWithoutAnimating() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(events: events, results: [.image])
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)

    let didSwitch = await transition.transition(
      direction: ISSDirectionLeft,
      duration: 0.25,
      canSwitch: { true },
      switchSpace: { true }
    )

    XCTAssertTrue(didSwitch)
    XCTAssertEqual(capture.captureCount, 1)
    XCTAssertEqual(presenter.animationCount, 0)
    XCTAssertEqual(presenter.removeCount, 1)
  }

  func testCancellationWhileWaitingForSpaceChangeRemovesOverlay() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(events: events, results: [.image])
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)
    var switchInvoked = false

    let task = Task { @MainActor in
      await transition.transition(
        direction: ISSDirectionRight,
        duration: 0.18,
        canSwitch: { true },
        switchSpace: { switchInvoked = true; return true }
      )
    }
    while !switchInvoked { await Task.yield() }
    task.cancel()
    let didSwitch = await task.value

    XCTAssertTrue(didSwitch)
    XCTAssertEqual(presenter.showCount, 1)
    XCTAssertEqual(presenter.removeCount, 1)
    XCTAssertEqual(capture.captureCount, 1)
  }

  func testSwitchFailureRemovesOverlayAndDoesNotCaptureDestination() async {
    let events = EventLog()
    let capture = FakeCaptureProvider(events: events, results: [.image])
    let presenter = FakeOverlayPresenter(events: events)
    let transition = makeTransition(capture: capture, presenter: presenter)
    var switchCount = 0

    let didSwitch = await transition.transition(
      direction: ISSDirectionRight,
      duration: 0.18,
      canSwitch: { true },
      switchSpace: { switchCount += 1; return false }
    )

    XCTAssertFalse(didSwitch)
    XCTAssertEqual(switchCount, 1)
    XCTAssertEqual(capture.captureCount, 1)
    XCTAssertEqual(presenter.showCount, 1)
    XCTAssertEqual(presenter.removeCount, 1)
  }

  private func makeTransition(
    capture: FakeCaptureProvider,
    presenter: FakeOverlayPresenter
  ) -> SpaceTransitionOverlay {
    SpaceTransitionOverlay(
      captureProvider: capture,
      presenter: presenter,
      screenProvider: { NSScreen.screens.first }
    )
  }
}

@MainActor
private final class FakeCaptureProvider: SpaceTransitionCaptureProviding {
  enum Result {
    case image
    case failure(SpaceTransitionCaptureError)
  }

  private let events: EventLog
  private var results: [Result]
  private(set) var captureCount = 0
  private(set) var excludedWindows: [CGWindowID?] = []

  init(events: EventLog, results: [Result]) {
    self.events = events
    self.results = results
  }

  func capture(screen: NSScreen, excludingWindow: CGWindowID?) async throws -> NSImage {
    events.append("capture")
    captureCount += 1
    excludedWindows.append(excludingWindow)
    switch results.removeFirst() {
    case .image:
      return NSImage(size: NSSize(width: 20, height: 20))
    case .failure(let error):
      throw error
    }
  }
}

@MainActor
private final class FakeOverlayPresenter: SpaceTransitionOverlayPresenting {
  private let events: EventLog
  var windowID: CGWindowID? { 42 }
  private(set) var showCount = 0
  private(set) var animationCount = 0
  private(set) var removeCount = 0

  init(events: EventLog) { self.events = events }

  func show(outgoingImage: NSImage, on screen: NSScreen) throws {
    events.append("show")
    showCount += 1
  }

  func animate(incomingImage: NSImage, direction: ISSDirection, duration: TimeInterval) async throws {
    events.append("animate")
    animationCount += 1
  }

  func remove() {
    events.append("remove")
    removeCount += 1
  }
}

@MainActor
private final class EventLog {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
}
