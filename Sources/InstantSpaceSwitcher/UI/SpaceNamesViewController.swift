import AppKit
import Combine

private final class SpaceNameField: NSTextField {
  var spaceKey: String?
}

final class SpaceNameFormatter: Formatter {
  override func string(for obj: Any?) -> String? { obj as? String }

  override func getObjectValue(
    _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
    errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
  ) -> Bool {
    obj?.pointee = string as NSString
    return true
  }

  override func isPartialStringValid(
    _ partialString: String, newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
    errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
  ) -> Bool {
    partialString.count <= SpaceNameStore.maximumNameLength
  }
}

private final class SpaceNamesStackView: NSStackView {
  override var isFlipped: Bool { true }
}

final class SpaceNamesViewController: NSViewController, NSTextFieldDelegate {
  private let store: SpaceNameStore
  private let stack = SpaceNamesStackView()
  private var cancellables = Set<AnyCancellable>()

  init(store: SpaceNameStore = .shared) {
    self.store = store
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 550, height: 350))
    let description = NSTextField(wrappingLabelWithString:
      "Names appear when switching spaces and in the Spaces menu. Leave a name empty to show its number. "
      + "Maximum \(SpaceNameStore.maximumNameLength) characters per name, including spaces.")
    description.textColor = .secondaryLabelColor
    description.translatesAutoresizingMaskIntoConstraints = false

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = stack

    let refresh = NSButton(title: "Refresh Spaces", target: self, action: #selector(refreshSpaces))
    refresh.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(description)
    view.addSubview(scroll)
    view.addSubview(refresh)
    NSLayoutConstraint.activate([
      description.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
      description.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      description.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scroll.topAnchor.constraint(equalTo: description.bottomAnchor, constant: 16),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      scroll.bottomAnchor.constraint(equalTo: refresh.topAnchor, constant: -12),
      stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      refresh.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      refresh.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    SpaceCatalog.shared.$displays.sink { [weak self] displays in
      self?.show(displays)
    }.store(in: &cancellables)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    SpaceCatalog.shared.refresh()
  }

  @objc private func refreshSpaces() {
    SpaceCatalog.shared.refresh()
  }

  func show(_ displays: [SpaceDisplay]) {
    for item in stack.arrangedSubviews {
      stack.removeArrangedSubview(item)
      item.removeFromSuperview()
    }
    if displays.isEmpty {
      stack.addArrangedSubview(NSTextField(labelWithString: "No accessible spaces. Try refreshing."))
    }
    for display in displays {
      let heading = NSTextField(labelWithString: display.name)
      heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
      stack.addArrangedSubview(heading)
      for space in display.spaces {
        let label = NSTextField(labelWithString: "Space \(space.index + 1)")
        label.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let field = SpaceNameField(string: store.name(for: space.identity.key) ?? "")
        field.spaceKey = space.identity.key
        field.delegate = self
        field.formatter = SpaceNameFormatter()
        field.isEnabled = space.identity.key != nil
        field.placeholderString = field.isEnabled ? "Space \(space.index + 1)" : "Name unavailable for this space"
        field.usesSingleLineMode = true
        field.setAccessibilityLabel("\(display.name), Space \(space.index + 1) name")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, field])
        row.distribution = .fill
        row.spacing = 12
        row.alignment = .centerY
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
      }
      stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)
    }
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    controlTextDidChange(notification)
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? SpaceNameField, let key = field.spaceKey else { return }
    if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
    store.setName(field.stringValue, for: key)
  }
}
