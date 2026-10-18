import Foundation
import ISS

func stringFromCStringBuffer<T>(_ buffer: T) -> String {
  var buffer = buffer
  return withUnsafeBytes(of: &buffer) {
    String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
  }
}

struct SpaceIdentity: Equatable {
  let key: String?

  init(displayIdentifier: String, identity: ISSSpaceIdentity) {
    let uuid = stringFromCStringBuffer(identity.uuid)
    if let uuid = UUID(uuidString: uuid) {
      key = "space:\(uuid.uuidString)"
    } else if uuid.isEmpty && identity.isDefaultDesktop && !displayIdentifier.isEmpty {
      key = "default:\(displayIdentifier.lowercased())"
    } else {
      key = nil
    }
  }
}

extension Notification.Name {
  static let spaceNamesDidChange = Notification.Name("SpaceNamesDidChange")
}

final class SpaceNameStore {
  static let shared = SpaceNameStore()
  static let maximumNameLength = 512
  private let defaults: UserDefaults
  private var names: [String: String]
  private static let defaultsKey = "customSpaceNames"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    names = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
  }

  func name(for key: String?) -> String? {
    guard let key else { return nil }
    return names[key]
  }

  @discardableResult
  func setName(_ name: String, for key: String) -> Bool {
    guard name.count <= Self.maximumNameLength else { return false }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = trimmed.isEmpty ? nil : trimmed
    guard names[key] != value else { return true }
    names[key] = value
    defaults.set(names, forKey: Self.defaultsKey)
    NotificationCenter.default.post(name: .spaceNamesDidChange, object: self)
    return true
  }

  func message(for event: ISSSwitchEvent) -> String {
    let identity = SpaceIdentity(
      displayIdentifier: stringFromCStringBuffer(event.display.displayID), identity: event.space)
    return name(for: identity.key) ?? String(UInt64(event.targetIndex) + 1)
  }
}
