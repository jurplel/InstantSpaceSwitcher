import AppKit
import XCTest
@testable import InstantSpaceSwitcher

@MainActor
final class SpaceNameInputTests: XCTestCase {
  private let workUUID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

  private func accepts(_ original: String, selection: NSRange, replacement: String) -> Bool {
    let proposed = (original as NSString).replacingCharacters(in: selection, with: replacement)
    return SpaceNameFormatter().isPartialStringValid(proposed, newEditingString: nil, errorDescription: nil)
  }

  private func display() -> SpaceDisplay {
    let raw: [[String: Any]] = [[
      "Display Identifier": "monitor-a",
      "Spaces": [["id64": 1, "uuid": workUUID, "type": 0]],
    ]]
    return SpaceCatalog.parse(raw, screenNames: ["monitor-a": "Monitor"], separateSpaces: true)[0]
  }

  private func field(in view: NSView) -> NSTextField? {
    if let field = view as? NSTextField, field.isEditable { return field }
    return view.subviews.lazy.compactMap { self.field(in: $0) }.first
  }

  private func withField(
    _ body: (SpaceNamesViewController, SpaceNameStore, UserDefaults, NSPanel, NSTextField, NSTextView) -> Void
  ) {
    _ = NSApplication.shared
    let suite = "SpaceNameInputTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SpaceNameStore(defaults: defaults)
    let controller = SpaceNamesViewController(store: store)
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
      styleMask: [.titled], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    defer { panel.close() }
    panel.contentView = controller.view
    controller.show([display()])
    controller.view.layoutSubtreeIfNeeded()
    let field = field(in: controller.view)!
    XCTAssertTrue(panel.makeFirstResponder(field))
    let editor = panel.firstResponder as! NSTextView
    body(controller, store, defaults, panel, field, editor)
  }

  func testTypingStopsAtCharacterLimit() {
    let original = String(repeating: "я", count: 511)
    XCTAssertTrue(accepts(original, selection: NSRange(location: 511, length: 0), replacement: "я"))
    XCTAssertFalse(accepts(original + "я", selection: NSRange(location: 512, length: 0), replacement: "!"))
  }

  func testOverflowingPasteIsRejectedAsAWhole() {
    let accepted = String(repeating: "я", count: 512)
    XCTAssertTrue(accepts("", selection: NSRange(location: 0, length: 0), replacement: accepted))
    XCTAssertFalse(accepts("", selection: NSRange(location: 0, length: 0), replacement: accepted + "tail"))
    XCTAssertFalse(accepts("Work", selection: NSRange(location: 0, length: 4), replacement: accepted + "tail"))
  }

  func testSelectionReplacementMustFitAlongsideExistingText() {
    let prefix = String(repeating: "a", count: 250)
    let suffix = String(repeating: "z", count: 260)
    XCTAssertTrue(accepts(prefix + suffix, selection: NSRange(location: 250, length: 0), replacement: "12"))
    XCTAssertFalse(accepts(prefix + suffix, selection: NSRange(location: 250, length: 0), replacement: "123"))
    XCTAssertTrue(accepts(prefix + "XY" + suffix, selection: NSRange(location: 250, length: 2), replacement: "12"))
    XCTAssertFalse(accepts(prefix + "XY" + suffix, selection: NSRange(location: 250, length: 2), replacement: "123"))
    XCTAssertTrue(accepts(String(repeating: "a", count: 1024),
      selection: NSRange(location: 0, length: 1024), replacement: "Short"))
  }

  func testEmojiAndDecomposedLettersCountAsWholeCharacters() {
    let prefix = "👩🏽‍💻" + String(repeating: "x", count: 509)
    let selection = NSRange(location: prefix.utf16.count, length: 0)
    XCTAssertTrue(accepts(prefix + "🚀", selection: selection, replacement: "e\u{301}"))
    XCTAssertFalse(accepts(prefix + "🚀", selection: selection, replacement: "e\u{301}👨‍👩‍👧‍👦"))
    let emoji = String(repeating: "👩🏽‍💻", count: 512)
    XCTAssertTrue(accepts("", selection: NSRange(location: 0, length: 0), replacement: emoji))
    XCTAssertFalse(accepts("", selection: NSRange(location: 0, length: 0), replacement: emoji + "👩🏽‍💻"))
  }

  func testNativeFieldRejectsOverflowPreservesUndoAndSurvivesRebuild() {
    withField { controller, store, defaults, panel, field, editor in
      let key = display().spaces[0].identity.key!
      let original = String(repeating: "a", count: 511)
      editor.insertText(original, replacementRange: editor.selectedRange())
      editor.breakUndoCoalescing()
      editor.undoManager?.removeAllActions()
      editor.insertText("👩🏽‍💻", replacementRange: editor.selectedRange())
      let accepted = original + "👩🏽‍💻"
      XCTAssertEqual(editor.string, accepted)
      XCTAssertEqual(field.stringValue, accepted)
      XCTAssertEqual(store.name(for: key), accepted)
      XCTAssertEqual(SpaceNameStore(defaults: defaults).name(for: key), accepted)

      let caret = editor.selectedRange()
      editor.insertText("!", replacementRange: caret)
      XCTAssertEqual(editor.string, accepted)
      XCTAssertEqual(editor.selectedRange(), caret)
      let selection = NSRange(location: 250, length: 2)
      editor.setSelectedRange(selection)
      editor.insertText("too long", replacementRange: selection)
      XCTAssertEqual(editor.string, accepted)
      XCTAssertEqual(editor.selectedRange(), selection)
      XCTAssertEqual(store.name(for: key), accepted)

      XCTAssertTrue(editor.undoManager?.canUndo == true)
      editor.undoManager?.undo()
      XCTAssertEqual(editor.string, original)
      XCTAssertTrue(panel.makeFirstResponder(nil))
      XCTAssertEqual(store.name(for: key), original)
      XCTAssertEqual(SpaceNameStore(defaults: defaults).name(for: key), original)

      XCTAssertTrue(panel.makeFirstResponder(field))
      let resumedEditor = panel.firstResponder as! NSTextView
      resumedEditor.setSelectedRange(NSRange(location: 0, length: resumedEditor.string.utf16.count))
      resumedEditor.insertText(accepted, replacementRange: resumedEditor.selectedRange())
      XCTAssertEqual(store.name(for: key), accepted)
      XCTAssertTrue(panel.makeFirstResponder(nil))
      controller.show([])
      controller.show([display()])
      XCTAssertEqual(self.field(in: controller.view)?.stringValue, accepted)
    }
  }

  func testMarkedTextIsSavedOnlyAfterCompositionCommits() {
    withField { _, store, _, _, field, editor in
      let key = display().spaces[0].identity.key!
      editor.insertText("Work", replacementRange: editor.selectedRange())
      editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
      editor.setMarkedText("Раб", selectedRange: NSRange(location: 3, length: 0),
        replacementRange: editor.selectedRange())
      XCTAssertTrue(editor.hasMarkedText())
      XCTAssertEqual(store.name(for: key), "Work")
      editor.insertText("Работа", replacementRange: editor.markedRange())
      XCTAssertFalse(editor.hasMarkedText())
      XCTAssertEqual(field.stringValue, "Работа")
      XCTAssertEqual(store.name(for: key), "Работа")
    }
  }
}
