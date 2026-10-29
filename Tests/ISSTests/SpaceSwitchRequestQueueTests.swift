import XCTest
@testable import InstantSpaceSwitcher

@MainActor
final class SpaceSwitchRequestQueueTests: XCTestCase {
  func testEnqueuedOperationsRunInArrivalOrderWithoutOverlapping() async {
    let queue = SpaceSwitchRequestQueue()
    let firstStarted = expectation(description: "first operation starts")
    let secondFinished = expectation(description: "second operation finishes")
    var events: [String] = []
    var activeOperations = 0
    var maximumActiveOperations = 0
    var releaseFirstOperation: CheckedContinuation<Void, Never>?

    queue.enqueue {
      activeOperations += 1
      maximumActiveOperations = max(maximumActiveOperations, activeOperations)
      events.append("first-start")
      firstStarted.fulfill()
      await withCheckedContinuation { continuation in
        releaseFirstOperation = continuation
      }
      events.append("first-end")
      activeOperations -= 1
    }

    queue.enqueue {
      activeOperations += 1
      maximumActiveOperations = max(maximumActiveOperations, activeOperations)
      events.append("second-start")
      activeOperations -= 1
      events.append("second-end")
      secondFinished.fulfill()
    }

    await fulfillment(of: [firstStarted], timeout: 1)
    await Task.yield()
    XCTAssertEqual(events, ["first-start"])
    XCTAssertEqual(maximumActiveOperations, 1)

    releaseFirstOperation?.resume()
    await fulfillment(of: [secondFinished], timeout: 1)

    XCTAssertEqual(events, ["first-start", "first-end", "second-start", "second-end"])
    XCTAssertEqual(maximumActiveOperations, 1)
    XCTAssertEqual(activeOperations, 0)
  }
}
