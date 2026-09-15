import AppKit
import ApplicationServices
import ISS

@MainActor
final class WindowSpaceMover {
  private let missionControlDelay: TimeInterval = 0.35
  private var moving = false

  func moveActiveWindow(to spaceIndex: UInt32, completion: @escaping (Bool) -> Void) {
    guard !moving else { completion(false); return }

    let missionControl = missionControlGroup()
    if let missionControl {
      guard let source = windowTile(at: NSEvent.mouseLocation, in: missionControl),
            let target = desktopTile(number: Int(spaceIndex) + 1, for: source.displayID, in: missionControl)
      else { completion(false); return }
      drag(from: source.center, to: target, closeMissionControl: false, completion: completion)
      return
    }

    guard let focused = focusedWindow(), let title = stringAttribute(focused, kAXTitleAttribute),
          let frame = frameAttribute(focused), let displayID = displayContaining(frame.midpoint)
    else { completion(false); return }

    guard iss_toggle_mission_control() else { completion(false); return }
    moving = true
    waitForMissionControl(attemptsRemaining: 8) { [weak self] group in
      guard let self else { completion(false); return }
      guard let group,
            let source = self.uniqueWindowTile(matching: title, displayID: displayID, in: group),
            let target = self.desktopTile(number: Int(spaceIndex) + 1, for: displayID, in: group)
      else {
        self.closeAfterFailure(completion)
        return
      }
      self.drag(from: source.center, to: target, closeMissionControl: true, completion: completion)
    }
  }

  private func closeAfterFailure(_ completion: @escaping (Bool) -> Void) {
    _ = iss_toggle_mission_control()
    moving = false
    completion(false)
  }

  private func waitForMissionControl(
    attemptsRemaining: Int, completion: @escaping (AXUIElement?) -> Void
  ) {
    DispatchQueue.main.asyncAfter(deadline: .now() + missionControlDelay) { [weak self] in
      guard let self else { completion(nil); return }
      if let group = self.missionControlGroup() { completion(group); return }
      guard attemptsRemaining > 0 else { completion(nil); return }
      self.waitForMissionControl(attemptsRemaining: attemptsRemaining - 1, completion: completion)
    }
  }

  private func drag(
    from start: CGPoint, to end: CGPoint, closeMissionControl: Bool,
    completion: @escaping (Bool) -> Void
  ) {
    let originalLocation = NSEvent.mouseLocation
    moving = true
    postMouse(.mouseMoved, at: start)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
      guard let self else { completion(false); return }
      self.postMouse(.leftMouseDown, at: start)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
        self.postMouse(.leftMouseDragged, at: end)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
          self.postMouse(.leftMouseUp, at: end)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.postMouse(.mouseMoved, at: originalLocation)
            if closeMissionControl { _ = iss_toggle_mission_control() }
            self.moving = false
            completion(true)
          }
        }
      }
    }
  }

  private func postMouse(_ type: CGEventType, at point: CGPoint) {
    guard let event = CGEvent(
      mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left
    ) else { return }
    event.flags = []
    event.post(tap: .cghidEventTap)
  }

  private func focusedWindow() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    guard let app = elementAttribute(system, kAXFocusedApplicationAttribute) else { return nil }
    return elementAttribute(app, kAXFocusedWindowAttribute)
  }

  private func missionControlGroup() -> AXUIElement? {
    guard let dock = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.apple.dock").first
    else { return nil }
    return descendants(of: AXUIElementCreateApplication(dock.processIdentifier)).first {
      stringAttribute($0, kAXIdentifierAttribute) == "mc"
    }
  }

  private func uniqueWindowTile(
    matching title: String, displayID: CGDirectDisplayID, in group: AXUIElement
  ) -> Tile? {
    let matches = windowTiles(in: group).filter {
      $0.displayID == displayID && (stringAttribute($0.element, kAXTitleAttribute) ?? "").contains(title)
    }
    guard matches.count == 1 else { return nil }
    return matches[0]
  }

  private func windowTile(at point: CGPoint, in group: AXUIElement) -> Tile? {
    windowTiles(in: group).first { $0.frame.contains(point) }
  }

  private func windowTiles(in group: AXUIElement) -> [Tile] {
    descendants(of: group)
      .filter { stringAttribute($0, kAXIdentifierAttribute) == "mc.windows" }
      .flatMap(children(of:))
      .compactMap { element in
      guard let frame = frameAttribute(element),
            let display = displayContaining(frame.midpoint)
      else { return nil }
      return Tile(element: element, frame: frame, displayID: display)
    }
  }

  private func desktopTile(number: Int, for displayID: CGDirectDisplayID, in group: AXUIElement) -> CGPoint? {
    guard let display = descendants(of: group).first(where: {
      integerAttribute($0, "AXDisplayID") == Int(displayID)
    }), let list = descendants(of: display).first(where: {
      stringAttribute($0, kAXIdentifierAttribute) == "mc.spaces.list"
    }) else { return nil }
    let desktops = children(of: list)
    guard number > 0, number <= desktops.count, let frame = frameAttribute(desktops[number - 1]) else {
      return nil
    }
    return frame.midpoint
  }

  private func displayContaining(_ point: CGPoint) -> CGDirectDisplayID? {
    var display: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count == 1 else {
      return nil
    }
    return display
  }

  private func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let array = value as? [AXUIElement]
    else { return [] }
    return array
  }

  private func descendants(of element: AXUIElement) -> [AXUIElement] {
    let direct = children(of: element)
    return direct + direct.flatMap(descendants(of:))
  }

  private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
  }

  private func integerAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? Int
  }

  private func frameAttribute(_ element: AXUIElement) -> CGRect? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
          let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID()
    else { return nil }
    var frame = CGRect.zero
    guard AXValueGetValue((axValue as! AXValue), .cgRect, &frame) else { return nil }
    return frame
  }

  private struct Tile {
    let element: AXUIElement
    let frame: CGRect
    let displayID: CGDirectDisplayID
    var center: CGPoint { frame.midpoint }
  }
}

private extension CGRect {
  var midpoint: CGPoint { CGPoint(x: midX, y: midY) }
}
