import AppKit

final class SpaceDisplayMapping {
  static let shared = SpaceDisplayMapping()

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Returns the CGDirectDisplayID assigned to a space slot (1-based), or 0 for "current display".
  func displayID(forSpaceSlot slot: Int) -> CGDirectDisplayID {
    return CGDirectDisplayID(defaults.integer(forKey: "spaceDisplay.\(slot)"))
  }

  func setDisplayID(_ displayID: CGDirectDisplayID, forSpaceSlot slot: Int) {
    defaults.set(Int(displayID), forKey: "spaceDisplay.\(slot)")
  }

  /// Calculates the local (per-display) space index for a given slot.
  /// Counts how many earlier slots share the same display assignment.
  func localSpaceIndex(forSpaceSlot slot: Int) -> UInt32 {
    let targetDisplayID = displayID(forSpaceSlot: slot)
    var localIndex: UInt32 = 0
    for s in 1..<slot {
      if displayID(forSpaceSlot: s) == targetDisplayID {
        localIndex += 1
      }
    }
    return localIndex
  }

  func resetAll() {
    for slot in 1...10 {
      defaults.removeObject(forKey: "spaceDisplay.\(slot)")
    }
  }
}
