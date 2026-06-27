import AppKit
import Carbon
@testable import InstantSpaceSwitcher
import XCTest

final class HotkeyCombinationTests: XCTestCase {
    private let optionFlags = UInt64(NSEvent.ModifierFlags.option.rawValue)
    private let controlOptionFlags =
        UInt64(NSEvent.ModifierFlags([.control, .option]).rawValue)
    private let rightOptionDeviceFlag: UInt64 = 0x00000040

    func testGenericOptionDoesNotMatchAdditionalControl() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )

        XCTAssertTrue(combination.matches(eventModifierFlags: optionFlags))
        XCTAssertFalse(combination.matches(eventModifierFlags: controlOptionFlags))
    }

    func testGenericOptionDoesNotMatchRightOption() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )

        XCTAssertFalse(combination.matches(eventModifierFlags: optionFlags | rightOptionDeviceFlag))
    }

    func testAltGrRequiresRightOption() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1",
            optionKeyKind: .right
        )

        XCTAssertFalse(combination.matches(eventModifierFlags: optionFlags))
        XCTAssertTrue(combination.matches(eventModifierFlags: optionFlags | rightOptionDeviceFlag))
    }

    func testLegacyDecodedShortcutDefaultsToGenericOption() throws {
        let json = """
        {
          "keyCode": \(kVK_ANSI_1),
          "modifiers": \(optionKey),
          "displayKey": "1",
          "keyEquivalent": "1"
        }
        """

        let decoded = try JSONDecoder().decode(
            HotkeyCombination.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.optionKeyKind, .any)
        XCTAssertFalse(decoded.matches(eventModifierFlags: optionFlags | rightOptionDeviceFlag))
    }

    func testAltGrDisplayIsDistinctFromGenericOption() {
        let generic = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )
        let altGr = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1",
            optionKeyKind: .right
        )

        XCTAssertEqual(generic.displayString, "⌥1")
        XCTAssertEqual(altGr.displayString, "AltGr1")
        XCTAssertNotEqual(generic, altGr)
    }

    func testAltGrSpecificShortcutWinsOverGenericOption() {
        let generic = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )
        let altGr = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1",
            optionKeyKind: .right
        )

        XCTAssertEqual(
            HotKeyManager.preferredCombination(
                from: [generic, altGr],
                keyCode: UInt32(kVK_ANSI_1),
                eventModifierFlags: optionFlags | rightOptionDeviceFlag),
            altGr
        )
    }

    func testNoShortcutSelectedForWrongKeyCode() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )

        XCTAssertNil(
            HotKeyManager.preferredCombination(
                from: [combination],
                keyCode: UInt32(kVK_ANSI_2),
                eventModifierFlags: optionFlags)
        )
    }
}
