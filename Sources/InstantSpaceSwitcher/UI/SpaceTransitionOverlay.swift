import AppKit
import CoreGraphics
import ISS
import QuartzCore

internal enum SpaceTransitionCaptureError: Error, Equatable {
  case screenRecordingPermissionDenied
  case noDisplayForCursor
  case captureFailed

  static let screenRecordingSettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
  )!
}

@MainActor
internal protocol SpaceTransitionCaptureProviding {
  func capture(screen: NSScreen, excludingWindow: CGWindowID?) async throws -> NSImage
}

@MainActor
internal protocol SpaceTransitionOverlayPresenting: AnyObject {
  var windowID: CGWindowID? { get }
  func show(outgoingImage: NSImage, on screen: NSScreen) throws
  func animate(incomingImage: NSImage, direction: ISSDirection, duration: TimeInterval) async throws
  func remove()
}

@MainActor
internal final class SpaceTransitionOverlay {
  private let captureProvider: SpaceTransitionCaptureProviding
  private let presenter: SpaceTransitionOverlayPresenting
  private let screenProvider: () -> NSScreen?
  private(set) var lastCaptureError: SpaceTransitionCaptureError?

  init(
    captureProvider: SpaceTransitionCaptureProviding? = nil,
    presenter: SpaceTransitionOverlayPresenting? = nil,
    screenProvider: @escaping () -> NSScreen? = {
      let cursorLocation = NSEvent.mouseLocation
      return NSScreen.screens.first(where: { $0.frame.contains(cursorLocation) })
        ?? NSScreen.main
    }
  ) {
    self.captureProvider = captureProvider ?? DesktopSpaceTransitionCaptureProvider()
    self.presenter = presenter ?? DesktopSpaceTransitionOverlayPresenter()
    self.screenProvider = screenProvider
  }

  func transition(
    direction: ISSDirection,
    duration: TimeInterval,
    canSwitch: @escaping () -> Bool,
    switchSpace: @escaping () -> Bool
  ) async -> Bool {
    lastCaptureError = nil
    guard canSwitch(), !Task.isCancelled else { return false }
    guard let screen = screenProvider() else { return switchSpace() }

    let outgoingImage: NSImage
    do {
      outgoingImage = try await captureProvider.capture(screen: screen, excludingWindow: nil)
    } catch let error as SpaceTransitionCaptureError {
      lastCaptureError = error
      return Task.isCancelled ? false : switchSpace()
    } catch {
      lastCaptureError = .captureFailed
      return Task.isCancelled ? false : switchSpace()
    }

    guard !Task.isCancelled else { return false }
    do {
      try presenter.show(outgoingImage: outgoingImage, on: screen)
    } catch {
      presenter.remove()
      return switchSpace()
    }

    defer { presenter.remove() }
    let spaceChangeObserver = ActiveSpaceChangeObserver()
    guard switchSpace() else {
      spaceChangeObserver.stop()
      return false
    }

    guard await spaceChangeObserver.wait(timeout: 1.0), !Task.isCancelled else {
      return true
    }

    do {
      let incomingImage = try await captureProvider.capture(
        screen: screen,
        excludingWindow: presenter.windowID
      )
      guard !Task.isCancelled else { return true }
      try await presenter.animate(
        incomingImage: incomingImage,
        direction: direction,
        duration: max(0, duration)
      )
    } catch let error as SpaceTransitionCaptureError {
      lastCaptureError = error
    } catch {
      lastCaptureError = .captureFailed
    }
    return true
  }
}

@MainActor
private final class DesktopSpaceTransitionCaptureProvider: SpaceTransitionCaptureProviding {
  func capture(screen: NSScreen, excludingWindow: CGWindowID?) async throws -> NSImage {
    guard CGPreflightScreenCaptureAccess() else {
      throw SpaceTransitionCaptureError.screenRecordingPermissionDenied
    }
    guard
      let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        as? CGDirectDisplayID
    else {
      throw SpaceTransitionCaptureError.noDisplayForCursor
    }

    let option: CGWindowListOption = excludingWindow == nil
      ? .optionOnScreenOnly
      : .optionOnScreenBelowWindow
    let image = CGWindowListCreateImage(
      CGDisplayBounds(displayNumber),
      option,
      excludingWindow ?? kCGNullWindowID,
      [.bestResolution, .boundsIgnoreFraming]
    )
    guard let image else { throw SpaceTransitionCaptureError.captureFailed }
    return NSImage(cgImage: image, size: screen.frame.size)
  }
}

@MainActor
private final class DesktopSpaceTransitionOverlayPresenter: SpaceTransitionOverlayPresenting {
  private final class OverlayView: NSView {
    override var isFlipped: Bool { true }

    let outgoingView = NSImageView()
    let incomingView = NSImageView()

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      for imageView in [outgoingView, incomingView] {
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
      }
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  private var panel: NSPanel?
  private var overlayView: OverlayView?
  var windowID: CGWindowID? {
    guard let number = panel?.windowNumber, number > 0 else { return nil }
    return CGWindowID(number)
  }

  func show(outgoingImage: NSImage, on screen: NSScreen) throws {
    let panel = NSPanel(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
    view.outgoingView.frame = view.bounds
    view.incomingView.frame = .zero
    view.outgoingView.image = outgoingImage
    panel.contentView = view
    panel.isOpaque = true
    panel.backgroundColor = .black
    panel.hasShadow = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.ignoresMouseEvents = true
    panel.orderFrontRegardless()
    self.panel = panel
    self.overlayView = view
  }

  func animate(incomingImage: NSImage, direction: ISSDirection, duration: TimeInterval) async throws {
    guard let view = overlayView else { throw SpaceTransitionCaptureError.captureFailed }
    let height = view.bounds.height
    let outgoingOffset = SpaceTransitionSettings.outgoingOffset(for: direction, height: height)
    let incomingOffset = -outgoingOffset
    view.incomingView.image = incomingImage
    view.incomingView.frame = view.bounds.offsetBy(dx: 0, dy: incomingOffset)

    guard duration > 0 else {
      view.outgoingView.frame = view.bounds.offsetBy(dx: 0, dy: outgoingOffset)
      view.incomingView.frame = view.bounds
      return
    }

    await withCheckedContinuation { continuation in
      NSAnimationContext.runAnimationGroup { context in
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.outgoingView.animator().frame = view.bounds.offsetBy(dx: 0, dy: outgoingOffset)
        view.incomingView.animator().frame = view.bounds
      } completionHandler: {
        continuation.resume()
      }
    }
  }

  func remove() {
    panel?.orderOut(nil)
    panel = nil
    overlayView = nil
  }
}

@MainActor
private final class ActiveSpaceChangeObserver {
  private let center = NSWorkspace.shared.notificationCenter
  private var observer: NSObjectProtocol?
  private var continuation: CheckedContinuation<Bool, Never>?
  private var timeoutTask: Task<Void, Never>?
  private var didReceiveChange = false
  private var isStopped = false

  init() {
    observer = center.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.finish(receivedChange: true)
      }
    }
  }

  func wait(timeout: TimeInterval) async -> Bool {
    if didReceiveChange { return true }
    if isStopped { return false }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        if didReceiveChange || Task.isCancelled {
          finish(receivedChange: didReceiveChange)
          return
        }
        timeoutTask = Task { @MainActor [weak self] in
          do {
            try await Task.sleep(for: .seconds(timeout))
          } catch {
            return
          }
          self?.finish(receivedChange: false)
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(receivedChange: false) }
    }
  }

  func stop() {
    isStopped = true
    finish(receivedChange: false)
  }

  private func finish(receivedChange: Bool) {
    if receivedChange { didReceiveChange = true }
    if let observer {
      center.removeObserver(observer)
      self.observer = nil
    }
    timeoutTask?.cancel()
    timeoutTask = nil
    guard let continuation else { return }
    self.continuation = nil
    isStopped = true
    continuation.resume(returning: receivedChange)
  }
}
