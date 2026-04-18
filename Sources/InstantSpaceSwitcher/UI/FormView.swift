import AppKit

final class FormView: NSView {
  private let gridView = NSGridView()

  init() {
    super.init(frame: .zero)
    gridView.translatesAutoresizingMaskIntoConstraints = false
    gridView.columnSpacing = 16
    gridView.rowSpacing = 12
    addSubview(gridView)

    NSLayoutConstraint.activate([
      gridView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
      gridView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
      gridView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
      // Set a lower priority for the bottom constraint to allow the grid to grow
      // and ensure the top constraint always pins it to the top.
      gridView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var hasRows: Bool {
    return gridView.numberOfRows > 0
  }

  func addRow(label: NSView?, control: NSView) {
    let labelView = label ?? NSView()
    let row = gridView.addRow(with: [labelView, control])
    row.cell(at: 0).xPlacement = .trailing
    row.cell(at: 1).xPlacement = .leading
    
    // Set vertical alignment back to center
    row.cell(at: 0).yPlacement = .center
    row.cell(at: 1).yPlacement = .center
  }

  func addSectionHeading(_ title: String, control: NSView) {
    let label = NSTextField(labelWithString: title)
    let row = gridView.addRow(with: [label, control])
    row.cell(at: 0).xPlacement = .trailing
    row.cell(at: 1).xPlacement = .leading
    
    // Set vertical alignment back to center
    row.cell(at: 0).yPlacement = .center
    row.cell(at: 1).yPlacement = .center
  }

  func addSectionSpacing() {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
    gridView.addRow(with: [spacer, NSView()])
  }
  
  func addVerticalFiller() {
    let filler = NSView()
    filler.setContentHuggingPriority(.defaultLow, for: .vertical)
    gridView.addRow(with: [filler, NSView()])
  }
}
