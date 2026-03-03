import AppKit
import Carbon
import Foundation

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String
  var keyEquivalent: String

  var displayString: String {
    let modifierSymbols = HotkeyCombination.symbols(for: modifiers)
    return modifierSymbols + displayKey
  }

  var cocoaModifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    return flags
  }

  var isValid: Bool {
    modifiers != 0 && !displayKey.isEmpty
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "←",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.leftArrow)
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "→",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.rightArrow)
  )

  static func defaultForSpace(_ number: Int) -> HotkeyCombination {
    let keyCode: UInt32
    let displayKey: String
    let keyEquivalent: String

    switch number {
    case 1:
      keyCode = UInt32(kVK_ANSI_1)
      displayKey = "1"
      keyEquivalent = "1"
    case 2:
      keyCode = UInt32(kVK_ANSI_2)
      displayKey = "2"
      keyEquivalent = "2"
    case 3:
      keyCode = UInt32(kVK_ANSI_3)
      displayKey = "3"
      keyEquivalent = "3"
    case 4:
      keyCode = UInt32(kVK_ANSI_4)
      displayKey = "4"
      keyEquivalent = "4"
    case 5:
      keyCode = UInt32(kVK_ANSI_5)
      displayKey = "5"
      keyEquivalent = "5"
    case 6:
      keyCode = UInt32(kVK_ANSI_6)
      displayKey = "6"
      keyEquivalent = "6"
    case 7:
      keyCode = UInt32(kVK_ANSI_7)
      displayKey = "7"
      keyEquivalent = "7"
    case 8:
      keyCode = UInt32(kVK_ANSI_8)
      displayKey = "8"
      keyEquivalent = "8"
    case 9:
      keyCode = UInt32(kVK_ANSI_9)
      displayKey = "9"
      keyEquivalent = "9"
    case 10:
      keyCode = UInt32(kVK_ANSI_0)
      displayKey = "0"
      keyEquivalent = "0"
    default: fatalError("Invalid space number")
    }

    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: defaultModifierMask,
      displayKey: displayKey,
      keyEquivalent: keyEquivalent
    )
  }

  static func from(event: NSEvent) -> HotkeyCombination? {
    let modifiers = event.modifierFlags.carbonMask
    print(
      "[HotkeyCombination] from(event) - modifierFlags: \(event.modifierFlags), carbonMask: \(modifiers)"
    )
    guard modifiers != 0 else {
      print("[HotkeyCombination] No modifiers detected")
      return nil
    }

    let keyCode = UInt32(event.keyCode)
    if let special = event.specialKey, let symbol = arrowSymbol(for: special) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: symbol,
        keyEquivalent: arrowKeyEquivalent(special)
      )
    }

    guard let characters = event.charactersIgnoringModifiers, let first = characters.first else {
      return nil
    }

    let upper = String(first).uppercased()
    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: modifiers,
      displayKey: upper,
      keyEquivalent: String(first).lowercased()
    )
  }

  static func arrowSymbol(for specialKey: NSEvent.SpecialKey) -> String? {
    switch specialKey {
    case .leftArrow: return "←"
    case .rightArrow: return "→"
    case .upArrow: return "↑"
    case .downArrow: return "↓"
    default: return nil
    }
  }

  private static func arrowKeyEquivalent(_ specialKey: NSEvent.SpecialKey) -> String {
    switch specialKey {
    case .leftArrow:
      return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    case .rightArrow:
      return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    case .upArrow:
      return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    case .downArrow:
      return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    default:
      return ""
    }
  }

  private static func symbols(for modifiers: UInt32) -> String {
    var result = ""
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    return result
  }

  private static var defaultModifierMask: UInt32 {
    UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
  }
}

enum HotkeyIdentifier: String, CaseIterable {
  case left
  case right
  case space1, space2, space3, space4, space5
  case space6, space7, space8, space9, space10
}

final class HotkeyStore: ObservableObject {
  static let shared = HotkeyStore()

  @Published private(set) var leftHotkey: HotkeyCombination
  @Published private(set) var rightHotkey: HotkeyCombination
  @Published private(set) var space1Hotkey: HotkeyCombination
  @Published private(set) var space2Hotkey: HotkeyCombination
  @Published private(set) var space3Hotkey: HotkeyCombination
  @Published private(set) var space4Hotkey: HotkeyCombination
  @Published private(set) var space5Hotkey: HotkeyCombination
  @Published private(set) var space6Hotkey: HotkeyCombination
  @Published private(set) var space7Hotkey: HotkeyCombination
  @Published private(set) var space8Hotkey: HotkeyCombination
  @Published private(set) var space9Hotkey: HotkeyCombination
  @Published private(set) var space10Hotkey: HotkeyCombination
  @Published private(set) var enabledStates: [HotkeyIdentifier: Bool] = [:]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    leftHotkey = defaults.hotkey(forKey: DefaultsKey.left.rawValue) ?? .defaultLeft
    rightHotkey = defaults.hotkey(forKey: DefaultsKey.right.rawValue) ?? .defaultRight
    space1Hotkey = defaults.hotkey(forKey: DefaultsKey.space1.rawValue) ?? .defaultForSpace(1)
    space2Hotkey = defaults.hotkey(forKey: DefaultsKey.space2.rawValue) ?? .defaultForSpace(2)
    space3Hotkey = defaults.hotkey(forKey: DefaultsKey.space3.rawValue) ?? .defaultForSpace(3)
    space4Hotkey = defaults.hotkey(forKey: DefaultsKey.space4.rawValue) ?? .defaultForSpace(4)
    space5Hotkey = defaults.hotkey(forKey: DefaultsKey.space5.rawValue) ?? .defaultForSpace(5)
    space6Hotkey = defaults.hotkey(forKey: DefaultsKey.space6.rawValue) ?? .defaultForSpace(6)
    space7Hotkey = defaults.hotkey(forKey: DefaultsKey.space7.rawValue) ?? .defaultForSpace(7)
    space8Hotkey = defaults.hotkey(forKey: DefaultsKey.space8.rawValue) ?? .defaultForSpace(8)
    space9Hotkey = defaults.hotkey(forKey: DefaultsKey.space9.rawValue) ?? .defaultForSpace(9)
    space10Hotkey = defaults.hotkey(forKey: DefaultsKey.space10.rawValue) ?? .defaultForSpace(10)

    for identifier in HotkeyIdentifier.allCases {
      let key = "enabled.\(identifier.rawValue)"
      enabledStates[identifier] = defaults.object(forKey: key) as? Bool ?? true
    }
  }

  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    switch identifier {
    case .left:
      guard combination != leftHotkey else { return }
      leftHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.left.rawValue)
    case .right:
      guard combination != rightHotkey else { return }
      rightHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.right.rawValue)
    case .space1:
      guard combination != space1Hotkey else { return }
      space1Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space1.rawValue)
    case .space2:
      guard combination != space2Hotkey else { return }
      space2Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space2.rawValue)
    case .space3:
      guard combination != space3Hotkey else { return }
      space3Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space3.rawValue)
    case .space4:
      guard combination != space4Hotkey else { return }
      space4Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space4.rawValue)
    case .space5:
      guard combination != space5Hotkey else { return }
      space5Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space5.rawValue)
    case .space6:
      guard combination != space6Hotkey else { return }
      space6Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space6.rawValue)
    case .space7:
      guard combination != space7Hotkey else { return }
      space7Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space7.rawValue)
    case .space8:
      guard combination != space8Hotkey else { return }
      space8Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space8.rawValue)
    case .space9:
      guard combination != space9Hotkey else { return }
      space9Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space9.rawValue)
    case .space10:
      guard combination != space10Hotkey else { return }
      space10Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space10.rawValue)
    }
  }

  func resetToDefaults() {
    leftHotkey = .defaultLeft
    rightHotkey = .defaultRight
    space1Hotkey = .defaultForSpace(1)
    space2Hotkey = .defaultForSpace(2)
    space3Hotkey = .defaultForSpace(3)
    space4Hotkey = .defaultForSpace(4)
    space5Hotkey = .defaultForSpace(5)
    space6Hotkey = .defaultForSpace(6)
    space7Hotkey = .defaultForSpace(7)
    space8Hotkey = .defaultForSpace(8)
    space9Hotkey = .defaultForSpace(9)
    space10Hotkey = .defaultForSpace(10)

    defaults.setHotkey(leftHotkey, forKey: DefaultsKey.left.rawValue)
    defaults.setHotkey(rightHotkey, forKey: DefaultsKey.right.rawValue)
    defaults.setHotkey(space1Hotkey, forKey: DefaultsKey.space1.rawValue)
    defaults.setHotkey(space2Hotkey, forKey: DefaultsKey.space2.rawValue)
    defaults.setHotkey(space3Hotkey, forKey: DefaultsKey.space3.rawValue)
    defaults.setHotkey(space4Hotkey, forKey: DefaultsKey.space4.rawValue)
    defaults.setHotkey(space5Hotkey, forKey: DefaultsKey.space5.rawValue)
    defaults.setHotkey(space6Hotkey, forKey: DefaultsKey.space6.rawValue)
    defaults.setHotkey(space7Hotkey, forKey: DefaultsKey.space7.rawValue)
    defaults.setHotkey(space8Hotkey, forKey: DefaultsKey.space8.rawValue)
    defaults.setHotkey(space9Hotkey, forKey: DefaultsKey.space9.rawValue)
    defaults.setHotkey(space10Hotkey, forKey: DefaultsKey.space10.rawValue)
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    switch identifier {
    case .left: return leftHotkey
    case .right: return rightHotkey
    case .space1: return space1Hotkey
    case .space2: return space2Hotkey
    case .space3: return space3Hotkey
    case .space4: return space4Hotkey
    case .space5: return space5Hotkey
    case .space6: return space6Hotkey
    case .space7: return space7Hotkey
    case .space8: return space8Hotkey
    case .space9: return space9Hotkey
    case .space10: return space10Hotkey
    }
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    return enabledStates[identifier] ?? true
  }

  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) {
    enabledStates[identifier] = enabled
    let key = "enabled.\(identifier.rawValue)"
    defaults.set(enabled, forKey: key)
  }

  private enum DefaultsKey: String {
    case left = "hotkey.left"
    case right = "hotkey.right"
    case space1 = "hotkey.space1"
    case space2 = "hotkey.space2"
    case space3 = "hotkey.space3"
    case space4 = "hotkey.space4"
    case space5 = "hotkey.space5"
    case space6 = "hotkey.space6"
    case space7 = "hotkey.space7"
    case space8 = "hotkey.space8"
    case space9 = "hotkey.space9"
    case space10 = "hotkey.space10"
  }
}

extension UserDefaults {
  fileprivate func hotkey(forKey key: String) -> HotkeyCombination? {
    guard let data = data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(HotkeyCombination.self, from: data)
  }

  fileprivate func setHotkey(_ hotkey: HotkeyCombination, forKey key: String) {
    if let data = try? JSONEncoder().encode(hotkey) {
      set(data, forKey: key)
    }
  }
}

extension NSEvent.ModifierFlags {
  var carbonMask: UInt32 {
    var mask: UInt32 = 0
    if contains(.command) { mask |= UInt32(cmdKey) }
    if contains(.option) { mask |= UInt32(optionKey) }
    if contains(.control) { mask |= UInt32(controlKey) }
    if contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
  }
}
