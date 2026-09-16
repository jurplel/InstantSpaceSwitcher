import SpaceTransition
import XCTest

final class SpaceTransitionCoordinatorTests: XCTestCase {
  private let space1 = SpaceTransitionCoordinator.SpaceSnapshot(
    displayID: "display-a", currentIndex: 0, spaceCount: 4)
  private let space2 = SpaceTransitionCoordinator.SpaceSnapshot(
    displayID: "display-a", currentIndex: 1, spaceCount: 4)
  private let space3 = SpaceTransitionCoordinator.SpaceSnapshot(
    displayID: "display-a", currentIndex: 2, spaceCount: 4)

  func testOneRequestStartsOneTransition() {
    var coordinator = SpaceTransitionCoordinator()

    let effects = coordinator.request(.right, snapshot: space1)

    XCTAssertEqual(startedTransitions(in: effects).map(\.direction), [.right])
    XCTAssertTrue(coordinator.isTransitionInFlight)
  }

  func testConfirmationOnlyEffectIsDeferredUntilSpaceChange() {
    var coordinator = SpaceTransitionCoordinator()

    let requestEffects = coordinator.request(.right, snapshot: space1)
    XCTAssertTrue(confirmedTransitions(in: requestEffects).isEmpty)

    let confirmationEffects = coordinator.receiveSpaceChange(space2)
    XCTAssertEqual(confirmedTransitions(in: confirmationEffects).map(\.targetIndex), [1])
  }

  func testRapidRequestsQueueWithoutOverlap() {
    var coordinator = SpaceTransitionCoordinator()

    let firstEffects = coordinator.request(.right, snapshot: space1)
    let secondEffects = coordinator.request(.right, snapshot: nil)

    XCTAssertEqual(startedTransitions(in: firstEffects).count, 1)
    XCTAssertTrue(startedTransitions(in: secondEffects).isEmpty)
    XCTAssertEqual(coordinator.queueDepth, 1)
  }

  func testConfirmationStartsNextQueuedRequest() {
    var coordinator = SpaceTransitionCoordinator()
    _ = coordinator.request(.right, snapshot: space1)
    _ = coordinator.request(.right, snapshot: space1)

    let effects = coordinator.receiveSpaceChange(space2)

    XCTAssertEqual(confirmedTransitions(in: effects).map(\.targetIndex), [1])
    XCTAssertEqual(startedTransitions(in: effects).map(\.targetIndex), [2])
    XCTAssertTrue(coordinator.isTransitionInFlight)
  }

  func testDuplicateAndStaleConfirmationsAreHarmless() {
    var coordinator = SpaceTransitionCoordinator()
    _ = coordinator.request(.right, snapshot: space1)
    _ = coordinator.request(.right, snapshot: space1)
    _ = coordinator.receiveSpaceChange(space2)

    let duplicateEffects = coordinator.receiveSpaceChange(space2)
    let otherDisplay = SpaceTransitionCoordinator.SpaceSnapshot(
      displayID: "display-b", currentIndex: 2, spaceCount: 4)
    let staleEffects = coordinator.receiveSpaceChange(otherDisplay)

    XCTAssertTrue(confirmedTransitions(in: duplicateEffects).isEmpty)
    XCTAssertTrue(startedTransitions(in: duplicateEffects).isEmpty)
    XCTAssertTrue(confirmedTransitions(in: staleEffects).isEmpty)
    XCTAssertTrue(coordinator.isTransitionInFlight)
  }

  func testTimeoutRecoversWithoutStartingQueuedRequest() throws {
    var coordinator = SpaceTransitionCoordinator()
    let startEffects = coordinator.request(.right, snapshot: space1)
    let transition = try XCTUnwrap(startedTransitions(in: startEffects).first)
    _ = coordinator.request(.right, snapshot: space1)

    let timeoutEffects = coordinator.timeout(transitionID: transition.id)
    let recoveryRequestEffects = coordinator.request(.left, snapshot: space1)

    XCTAssertTrue(startedTransitions(in: timeoutEffects).isEmpty)
    XCTAssertEqual(coordinator.queueDepth, 0)
    XCTAssertTrue(coordinator.isRecovering)
    XCTAssertTrue(startedTransitions(in: recoveryRequestEffects).isEmpty)

    _ = coordinator.finishRecovery(transitionID: transition.id)
    let afterRecoveryEffects = coordinator.request(.right, snapshot: space1)
    XCTAssertEqual(startedTransitions(in: afterRecoveryEffects).count, 1)
  }

  func testOppositeDirectionsUseFIFOOrder() {
    var coordinator = SpaceTransitionCoordinator()
    _ = coordinator.request(.right, snapshot: space1)
    _ = coordinator.request(.left, snapshot: space1)

    let effects = coordinator.receiveSpaceChange(space2)

    XCTAssertEqual(startedTransitions(in: effects).map(\.direction), [.left])
    XCTAssertEqual(startedTransitions(in: effects).map(\.targetIndex), [0])
  }

  func testProjectedIndexIncludesInFlightAndQueuedDirections() {
    var coordinator = SpaceTransitionCoordinator()
    _ = coordinator.request(.right, snapshot: space1)
    _ = coordinator.request(.right, snapshot: space1)

    XCTAssertEqual(coordinator.projectedIndex(from: space1), space3.currentIndex)
  }

  private func startedTransitions(
    in effects: [SpaceTransitionCoordinator.Effect]
  ) -> [SpaceTransitionCoordinator.Transition] {
    effects.compactMap { effect in
      guard case .start(let transition, _) = effect else { return nil }
      return transition
    }
  }

  private func confirmedTransitions(
    in effects: [SpaceTransitionCoordinator.Effect]
  ) -> [SpaceTransitionCoordinator.Transition] {
    effects.compactMap { effect in
      guard case .confirmed(let transition, _) = effect else { return nil }
      return transition
    }
  }
}
