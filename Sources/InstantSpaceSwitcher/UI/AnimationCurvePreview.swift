import AppKit
import ISS

/// A graph of the timing curve used by the gesture driver.
final class AnimationCurvePreview: NSView {
  var settings = AnimationSettings() { didSet { needsDisplay = true } }
  override var intrinsicContentSize: NSSize { NSSize(width: 380, height: 155) }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("Animation timing curve")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    NSColor.controlBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
    let plot = NSRect(x: 36, y: 30, width: bounds.width - 54, height: bounds.height - 55)
    NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
    let grid = NSBezierPath()
    for i in 0...4 {
      let f = CGFloat(i) / 4
      grid.move(to: NSPoint(x: plot.minX + f * plot.width, y: plot.minY))
      grid.line(to: NSPoint(x: plot.minX + f * plot.width, y: plot.maxY))
      grid.move(to: NSPoint(x: plot.minX, y: plot.minY + f * plot.height))
      grid.line(to: NSPoint(x: plot.maxX, y: plot.minY + f * plot.height))
    }
    grid.lineWidth = 0.5
    grid.stroke()
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor
    ]
    ("100%" as NSString).draw(at: NSPoint(x: 4, y: plot.maxY - 6), withAttributes: attributes)
    ("0%" as NSString).draw(at: NSPoint(x: 12, y: plot.minY - 5), withAttributes: attributes)
    ("Time" as NSString).draw(at: NSPoint(x: plot.midX - 12, y: plot.minY - 18), withAttributes: attributes)
    let curve = NSBezierPath()
    for i in 0...160 {
      let t = Double(i) / 160
      let p = settings.isInstant ? (i == 0 ? 0 : 1) : iss_animation_progress(t, settings.easeIn, settings.easeOut)
      let point = NSPoint(x: plot.minX + t * plot.width, y: plot.minY + p * plot.height)
      if i == 0 { curve.move(to: point) } else { curve.line(to: point) }
    }
    NSColor.controlAccentColor.setStroke()
    curve.lineWidth = 2.5
    curve.stroke()

  }
}
