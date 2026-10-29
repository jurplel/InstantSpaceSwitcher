import Foundation

@MainActor
final class SpaceSwitchRequestQueue {
  private var operations: [() async -> Void] = []
  private var isProcessing = false

  func enqueue(_ operation: @escaping () async -> Void) {
    operations.append(operation)
    guard !isProcessing else { return }

    isProcessing = true
    Task { @MainActor in
      while !operations.isEmpty {
        let nextOperation = operations.removeFirst()
        await nextOperation()
      }
      isProcessing = false
    }
  }
}
