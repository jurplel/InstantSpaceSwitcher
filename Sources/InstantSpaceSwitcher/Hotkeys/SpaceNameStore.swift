import Foundation

final class SpaceNameStore {
  static let shared = SpaceNameStore()

  private let defaults = UserDefaults.standard
  private let keyPrefix = "spaceName."
  private let maxTrackedSpacesPerDisplay = 20

  private init() {}

  // MARK: - Per-display naming

  func name(forDisplayID displayID: UInt32, spaceIndex index: Int) -> String? {
    let value = defaults.string(forKey: "\(keyPrefix)\(displayID).\(index + 1)")
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  func setName(_ name: String?, forDisplayID displayID: UInt32, spaceIndex index: Int) {
    defaults.set(name, forKey: "\(keyPrefix)\(displayID).\(index + 1)")
  }

  /// Returns the custom name if set, otherwise the 1-based space number.
  func displayName(forDisplayID displayID: UInt32, spaceIndex index: Int) -> String {
    name(forDisplayID: displayID, spaceIndex: index) ?? "\(index + 1)"
  }

  /// Clears names for spaces beyond the given count on a specific display.
  func clearNames(forDisplayID displayID: UInt32, beyondCount count: Int) {
    for i in (count + 1)...maxTrackedSpacesPerDisplay {
      defaults.removeObject(forKey: "\(keyPrefix)\(displayID).\(i)")
    }
  }

  /// Clears all names for a specific display.
  func clearNames(forDisplayID displayID: UInt32) {
    for i in 1...maxTrackedSpacesPerDisplay {
      defaults.removeObject(forKey: "\(keyPrefix)\(displayID).\(i)")
    }
  }

  func resetAll() {
    // Clear all keys matching our prefix
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
      defaults.removeObject(forKey: key)
    }
  }

}
