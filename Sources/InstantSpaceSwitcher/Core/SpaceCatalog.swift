import AppKit
import Combine
import ISS

struct SpaceDescription: Equatable {
  let index: UInt32
  let identity: SpaceIdentity
}

struct SpaceDisplay: Equatable {
  let identifier: String
  let name: String
  let spaces: [SpaceDescription]
}

@MainActor
final class SpaceCatalog {
  static let shared = SpaceCatalog()
  @Published private(set) var displays: [SpaceDisplay] = []
  private var refreshWorkItem: DispatchWorkItem?
  private var cancellables = Set<AnyCancellable>()

  func startObserving() {
    guard cancellables.isEmpty else { return }
    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
      .merge(with: NSWorkspace.shared.notificationCenter.publisher(
        for: NSWorkspace.activeSpaceDidChangeNotification))
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.scheduleRefresh() }
      .store(in: &cancellables)
    refresh()
  }

  func scheduleRefresh() {
    refreshWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.refresh() }
    refreshWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
  }

  func refresh() {
    refreshWorkItem?.cancel()
    refreshWorkItem = nil
    guard let raw = iss_copy_managed_display_spaces() as? [[String: Any]] else {
      if !displays.isEmpty { displays = [] }
      return
    }
    let names = Self.screenNames()
    let updated = Self.parse(raw, screenNames: names, separateSpaces: NSScreen.screensHaveSeparateSpaces)
    if updated != displays { displays = updated }
  }

  func identity(displayIdentifier: String, index: UInt32) -> SpaceIdentity? {
    displays.first { $0.identifier == displayIdentifier }?.spaces.first { $0.index == index }?.identity
  }

  nonisolated static func parse(
    _ raw: [[String: Any]], screenNames: [String: String], separateSpaces: Bool
  ) -> [SpaceDisplay] {
    raw.enumerated().compactMap { offset, display in
      guard let identifier = display["Display Identifier"] as? String,
        let spaces = display["Spaces"] as? [Any] else { return nil }
      let descriptions = spaces.indices.compactMap { index -> SpaceDescription? in
        var identity = ISSSpaceIdentity()
        guard iss_get_space_identity(spaces as CFArray, UInt32(index), &identity) else { return nil }
        return SpaceDescription(
          index: UInt32(index), identity: SpaceIdentity(displayIdentifier: identifier, identity: identity))
      }
      return SpaceDisplay(
        identifier: identifier,
        name: separateSpaces ? (screenNames[identifier.lowercased()] ?? "Display \(offset + 1)") : "All Displays",
        spaces: descriptions)
    }
  }

  private static func screenNames() -> [String: String] {
    var names: [String: String] = [:]
    for screen in NSScreen.screens {
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
        let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
        let identifier = CFUUIDCreateString(nil, uuid) as String? else { continue }
      names[identifier.lowercased()] = screen.localizedName
    }
    return names
  }
}
