import AppKit
import XCTest
@testable import InstantSpaceSwitcher

@MainActor
final class OSDLayoutTests: XCTestCase {
  private func checkLayout(_ view: OSDContentView, message: String, maximumSize: NSSize) -> NSSize {
    let size = view.update(message: message, maximumSize: maximumSize)
    XCTAssertLessThanOrEqual(size.width, maximumSize.width)
    XCTAssertLessThanOrEqual(size.height, maximumSize.height)
    XCTAssertEqual(view.messageLabel.stringValue, message)
    XCTAssertEqual(view.messageLabel.lineBreakMode, .byWordWrapping)
    XCTAssertEqual(view.messageLabel.maximumNumberOfLines, 0)
    XCTAssertTrue(view.bounds.contains(view.messageLabel.frame))

    let storage = NSTextStorage(attributedString: view.messageLabel.attributedStringValue)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(
      width: view.messageLabel.bounds.width - 4, height: view.messageLabel.bounds.height))
    container.lineFragmentPadding = 0
    container.lineBreakMode = view.messageLabel.lineBreakMode
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    XCTAssertEqual(layout.glyphRange(for: container).length, layout.numberOfGlyphs)
    XCTAssertLessThanOrEqual(layout.usedRect(for: container).height, view.messageLabel.bounds.height)
    return size
  }

  func testNumbersKeepOriginalSize() {
    let view = OSDContentView(frame: .zero)
    let size = checkLayout(view, message: "16", maximumSize: NSSize(width: 1200, height: 800))
    XCTAssertEqual(size, NSSize(width: 140, height: 140))
    XCTAssertEqual(view.messageLabel.font?.pointSize, 48)
  }

  func testLongNameWrapsAndGrowsVertically() {
    let view = OSDContentView(frame: .zero)
    let message = String(repeating: "Работа над длинным названием рабочего стола ", count: 4)
    let size = checkLayout(view, message: message, maximumSize: NSSize(width: 1200, height: 800))
    XCTAssertGreaterThan(size.width, 140)
    XCTAssertGreaterThan(size.height, 140)
    XCTAssertEqual(view.messageLabel.font?.pointSize, 36)
  }

  func testLongWordWithoutSpacesIsFullyVisible() {
    let view = OSDContentView(frame: .zero)
    let size = checkLayout(view, message: String(repeating: "W", count: 120),
      maximumSize: NSSize(width: 900, height: 650))
    XCTAssertGreaterThan(size.height, 140)
  }

  func testUnicodeNamesFitOnNarrowDisplays() {
    let view = OSDContentView(frame: .zero)
    let message = String(repeating: "Разработка 👩🏽‍💻 文書 e\u{301} ", count: 8)
    _ = checkLayout(view, message: message, maximumSize: NSSize(width: 400, height: 700))
  }

  func testVeryLongNamesFitSmallDisplaysWithoutEllipsis() {
    let view = OSDContentView(frame: .zero)
    let message = String(repeating: "Документация и разработка приложения ", count: 60)
    _ = checkLayout(view, message: message, maximumSize: NSSize(width: 560, height: 320))
    XCTAssertLessThan(view.messageLabel.font!.pointSize, 36)
  }

  func testLayoutResetsBetweenLongAndShortNames() {
    let view = OSDContentView(frame: .zero)
    let maximumSize = NSSize(width: 1000, height: 600)
    let message = String(repeating: "Длинное название ", count: 40)
    let first = checkLayout(view, message: message, maximumSize: maximumSize)
    let short = checkLayout(view, message: "2", maximumSize: maximumSize)
    XCTAssertEqual(short, NSSize(width: 140, height: 140))
    XCTAssertEqual(view.messageLabel.font?.pointSize, 48)
    XCTAssertEqual(checkLayout(view, message: message, maximumSize: maximumSize), first)
  }
}
