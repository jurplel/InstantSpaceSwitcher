import Foundation

final class SpaceNameStore {
  static let shared = SpaceNameStore()

  private let defaults = UserDefaults.standard
  private let keyPrefix = "spaceNameByID."

  private init() {}

  // MARK: - Per-space naming (keyed by stable macOS space ID)

  func name(forSpaceID spaceID: UInt64) -> String? {
    guard spaceID != 0 else { return nil }
    let value = defaults.string(forKey: "\(keyPrefix)\(spaceID)")
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  func setName(_ name: String?, forSpaceID spaceID: UInt64) {
    guard spaceID != 0 else { return }
    defaults.set(name, forKey: "\(keyPrefix)\(spaceID)")
  }

  /// Returns the custom name if set, otherwise the 1-based space number.
  func displayName(forSpaceID spaceID: UInt64, fallbackIndex index: Int) -> String {
    name(forSpaceID: spaceID) ?? "\(index + 1)"
  }

  func resetAll() {
    for key in defaults.dictionaryRepresentation().keys
    where key.hasPrefix(keyPrefix) || key.hasPrefix("spaceName.") {
      defaults.removeObject(forKey: key)
    }
  }
}
