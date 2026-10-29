# Task 2 report: Desktop snapshot transition coordinator

## Implementation

Added `SpaceTransitionOverlay`, a main-actor coordinator with the requested asynchronous `transition(direction:duration:canSwitch:switchSpace:)` interface. Capture and presentation are behind injectable protocols so tests can model authorization failures, capture failures, ordering, animation, and cleanup without taking a real desktop screenshot.

The default capture implementation selects the display containing the pointer, checks Screen Recording authorization, and captures that display using the macOS 13-compatible Core Graphics window-list API. After the overlay is shown, destination capture is limited to content below the overlay window, preventing the overlay from appearing in its own snapshot. Permission denial is preserved as the distinguishable `screenRecordingPermissionDenied` error and exposes the Screen Recording settings URL through `SpaceTransitionCaptureError.screenRecordingSettingsURL`.

The borderless non-activating panel joins all Spaces and sits above normal windows. Its outgoing and incoming snapshots move by one display height, with a flipped view coordinate system so the existing `SpaceTransitionSettings.outgoingOffset` mapping produces upward motion for right switches and downward motion for left switches. The supplied duration is clamped at zero; existing preset mapping and OSD behavior/settings remain unchanged.

The coordinator checks `canSwitch` before capture, installs the active-space observer before calling the switch closure, waits at most one second for the notification, and removes the overlay on switch failure, timeout, cancellation, capture/animation errors, and success. Outgoing capture failure falls back to the switch closure without showing an overlay; destination failure never reverses a successful switch.

## Tests added

`Tests/ISSTests/SpaceTransitionOverlayTests.swift` covers:

- successful call ordering, both captures, overlay exclusion, and cleanup;
- `canSwitch == false` with no capture, presentation, or switch;
- denied Screen Recording permission, distinguishable error/settings route, and switch fallback;
- outgoing capture failure and switch fallback;
- destination capture failure without reversing the switch;
- a failed switch with cleanup and no destination capture;
- notification timeout without animation; and
- cancellation while waiting for the active-space notification with cleanup.

## Validation

- `swift build` — **PASS**.
- `swift test --filter SpaceTransitionOverlayTests` — **BLOCKED** before tests can run: this machine's active developer directory is `/Library/Developer/CommandLineTools`, which does not provide the `XCTest` module (`no such module 'XCTest'`).
- `swift test` — **BLOCKED** for the same missing `XCTest` module.
- `git diff --check` — **PASS**.

`xcodebuild -version` also confirms full Xcode is not installed/selected, so XCTest execution is unavailable in this environment. No project behavior outside the requested snapshot/overlay coordinator was changed.
