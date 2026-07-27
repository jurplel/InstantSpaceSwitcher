public struct SpaceTransitionCoordinator {
  public enum Direction: String, Equatable, Sendable {
    case left
    case right
  }

  public struct SpaceSnapshot: Equatable, Sendable {
    public let displayID: String
    public let currentIndex: Int
    public let spaceCount: Int

    public init(displayID: String, currentIndex: Int, spaceCount: Int) {
      self.displayID = displayID
      self.currentIndex = currentIndex
      self.spaceCount = spaceCount
    }
  }

  public struct Transition: Equatable, Sendable {
    public let id: UInt64
    public let direction: Direction
    public let displayID: String
    public let sourceIndex: Int
    public let targetIndex: Int
  }

  public enum Effect: Equatable, Sendable {
    case requested(direction: Direction, queueDepth: Int)
    case start(transition: Transition, queueDepth: Int)
    case confirmed(transition: Transition, queueDepth: Int)
    case blocked(direction: Direction, queueDepth: Int)
    case ignoredConfirmation(transitionID: UInt64?)
    case timedOut(transition: Transition, droppedQueueDepth: Int)
    case injectionFailed(transition: Transition, droppedQueueDepth: Int)
    case spaceInfoUnavailable(direction: Direction)
    case rejectedDuringRecovery(direction: Direction)
    case reconciled(transitionID: UInt64)
  }

  private enum State: Equatable {
    case idle
    case inFlight(Transition)
    case recovering(Transition)
  }

  private var state = State.idle
  private var queue: [Direction] = []
  private var nextTransitionID: UInt64 = 1

  public init() {}

  public var queueDepth: Int {
    queue.count
  }

  public var isTransitionInFlight: Bool {
    if case .inFlight = state { return true }
    return false
  }

  public var isRecovering: Bool {
    if case .recovering = state { return true }
    return false
  }

  public func projectedIndex(from snapshot: SpaceSnapshot) -> Int {
    var index = snapshot.currentIndex

    if case .inFlight(let transition) = state, transition.displayID == snapshot.displayID {
      index = transition.targetIndex
    }

    for direction in queue {
      index = targetIndex(for: direction, from: index, spaceCount: snapshot.spaceCount) ?? index
    }

    return index
  }

  public mutating func request(
    _ direction: Direction,
    snapshot: SpaceSnapshot?
  ) -> [Effect] {
    guard !isRecovering else {
      return [.rejectedDuringRecovery(direction: direction)]
    }

    if case .inFlight = state {
      queue.append(direction)
      return [.requested(direction: direction, queueDepth: queue.count)]
    }

    guard let snapshot else {
      return [.spaceInfoUnavailable(direction: direction)]
    }

    queue.append(direction)
    var effects: [Effect] = [.requested(direction: direction, queueDepth: queue.count)]
    effects.append(contentsOf: startNext(using: snapshot))
    return effects
  }

  public mutating func receiveSpaceChange(_ snapshot: SpaceSnapshot?) -> [Effect] {
    switch state {
    case .idle:
      return [.ignoredConfirmation(transitionID: nil)]
    case .recovering(let transition):
      state = .idle
      return [.reconciled(transitionID: transition.id)]
    case .inFlight(let transition):
      guard let snapshot,
        snapshot.displayID == transition.displayID,
        snapshot.currentIndex == transition.targetIndex
      else {
        return [.ignoredConfirmation(transitionID: transition.id)]
      }

      state = .idle
      var effects: [Effect] = [
        .confirmed(transition: transition, queueDepth: queue.count)
      ]
      effects.append(contentsOf: startNext(using: snapshot))
      return effects
    }
  }

  public mutating func injectionFailed(transitionID: UInt64) -> [Effect] {
    guard case .inFlight(let transition) = state, transition.id == transitionID else {
      return []
    }

    let droppedQueueDepth = queue.count
    queue.removeAll()
    state = .recovering(transition)
    return [
      .injectionFailed(transition: transition, droppedQueueDepth: droppedQueueDepth)
    ]
  }

  public mutating func timeout(transitionID: UInt64) -> [Effect] {
    guard case .inFlight(let transition) = state, transition.id == transitionID else {
      return []
    }

    let droppedQueueDepth = queue.count
    queue.removeAll()
    state = .recovering(transition)
    return [.timedOut(transition: transition, droppedQueueDepth: droppedQueueDepth)]
  }

  public mutating func finishRecovery(transitionID: UInt64) -> [Effect] {
    guard case .recovering(let transition) = state, transition.id == transitionID else {
      return []
    }

    state = .idle
    return [.reconciled(transitionID: transition.id)]
  }

  private mutating func startNext(using snapshot: SpaceSnapshot) -> [Effect] {
    var effects: [Effect] = []

    while !queue.isEmpty {
      let direction = queue.removeFirst()
      guard
        let targetIndex = targetIndex(
          for: direction,
          from: snapshot.currentIndex,
          spaceCount: snapshot.spaceCount
        )
      else {
        effects.append(.blocked(direction: direction, queueDepth: queue.count))
        continue
      }

      let transition = Transition(
        id: nextTransitionID,
        direction: direction,
        displayID: snapshot.displayID,
        sourceIndex: snapshot.currentIndex,
        targetIndex: targetIndex
      )
      nextTransitionID &+= 1
      state = .inFlight(transition)
      effects.append(.start(transition: transition, queueDepth: queue.count))
      break
    }

    return effects
  }

  private func targetIndex(
    for direction: Direction,
    from currentIndex: Int,
    spaceCount: Int
  ) -> Int? {
    guard currentIndex >= 0, currentIndex < spaceCount else { return nil }

    switch direction {
    case .left:
      return currentIndex > 0 ? currentIndex - 1 : nil
    case .right:
      return currentIndex + 1 < spaceCount ? currentIndex + 1 : nil
    }
  }
}
