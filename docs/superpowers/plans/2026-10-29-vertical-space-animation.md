# Vertical Space Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native horizontal space-switch animation with a customizable vertical slide of captured desktop snapshots while keeping existing space navigation.

**Architecture:** Add a main-actor transition coordinator that captures the current display, covers the native switch, observes the destination space, captures it, and animates both snapshots vertically. Keep the existing switch API and OSD; connect the coordinator at app-initiated switching entry points and use the existing gesture-speed preference to select overlay duration.

**Tech Stack:** Swift 5.9, AppKit, ScreenCaptureKit, XCTest, macOS 13+.

**Spec:** `docs/superpowers/specs/2026-10-29-vertical-space-animation-design.md`

## Global Constraints

- The package supports macOS 13 and later.
- Require Screen Recording permission for desktop snapshots; denied or failed capture must not prevent switching.
- Preserve left/right hotkey behavior and existing space bounds checks.
- Keep the existing OSD independent and retain its current settings.
- Reuse existing Animation Speed presets; do not add animation controls.

## Review Focus

- Screen Recording permission is denied or revoked: complete a normal switch, show a clear permission explanation, and do not leave an overlay visible. Test permission denial through an injectable capture provider.
- Outgoing or destination capture fails: complete or retain the already-completed switch and remove the cover without stranding the user. Test each capture failure point.
- A hotkey targets the current space or is blocked at a boundary: do not show an overlay or capture unnecessarily. Test no-op and blocked switch paths.
- A second hotkey arrives during an animation: process switches in order without overlapping overlays or losing a request. Test queued left/right and direct-index requests.
- Multiple displays are connected or the overlay is visible to capture: use the cursor's display (matching `iss_get_space_info`), exclude the app's overlay, and do not cover other displays. Verify on a multi-display macOS setup.

---

### Task 1: Define overlay duration and direction

**Files:**
- Create: `Sources/InstantSpaceSwitcher/Core/SpaceTransitionSettings.swift`
- Create: `Tests/ISSTests/SpaceTransitionSettingsTests.swift`

**Interfaces:**
- Produces: `SpaceTransitionSettings.duration(forGestureSpeed: Double) -> TimeInterval`
- Produces: `SpaceTransitionSettings.outgoingOffset(for: ISSDirection, height: CGFloat) -> CGFloat`

- [ ] **Step 1: Write the failing tests**

Add tests that assert preset durations for the existing stored speeds:

| Stored speed | Duration |
|---:|---:|
| `40.0` | `0.35` seconds |
| `50.0` | `0.25` seconds |
| `60.0` | `0.18` seconds |
| `80.0` | `0.10` seconds |
| `2000.0` | `0.0` seconds |

Assert an unknown speed uses `0.0` seconds, matching the current UI fallback to “Instant”. Assert left moves the outgoing snapshot downward by one display height and right moves it upward by one display height.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --filter SpaceTransitionSettingsTests`
Expected: FAIL because the settings type is not defined.

- [ ] **Step 3: Implement `SpaceTransitionSettings`**

Implement the two pure functions with the preset values and direction mapping above. Add `@testable import InstantSpaceSwitcher` to the new test file.

- [ ] **Step 4: Run the focused test and verify it passes**

Run: `swift test --filter SpaceTransitionSettingsTests`
Expected: PASS for all duration and direction assertions.

### Task 2: Capture desktop snapshots and animate the overlay

**Files:**
- Create: `Sources/InstantSpaceSwitcher/UI/SpaceTransitionOverlay.swift`
- Test: `Tests/ISSTests/SpaceTransitionOverlayTests.swift`

**Interfaces:**
- Consumes: `SpaceTransitionSettings.duration(forGestureSpeed:)` and `outgoingOffset(for:height:)`.
- Produces: `@MainActor final class SpaceTransitionOverlay` with `func transition(direction: ISSDirection, duration: TimeInterval, canSwitch: @escaping () -> Bool, switchSpace: @escaping () -> Bool) async -> Bool`.
- Keep capture behind a small injectable provider so capture failures and permission denial can be verified without capturing a real desktop in unit tests.

- [ ] **Step 1: Add a testable capture-provider seam**

Define a private or internal capture protocol whose implementation returns a desktop image for the affected `NSScreen` and reports authorization/capture errors. The test seam must permit injecting outgoing-capture and destination-capture failures.

- [ ] **Step 2: Implement the capture and cover lifecycle**

Call `canSwitch` before capturing. If it returns false, return false without capturing or showing an overlay. Otherwise use an API available on macOS 13+ to capture the cursor's display, excluding the app's own overlay. Show a borderless, non-activating window above all spaces with the outgoing snapshot before invoking `switchSpace`. If the switch closure returns false, remove the cover and return false.

- [ ] **Step 3: Wait for the active-space change and capture the destination**

Observe `NSWorkspace.activeSpaceDidChangeNotification` for the switch initiated by the closure. Capture the destination while the overlay still covers the native transition; if no notification arrives within one second, remove the cover and finish without animation. Animate the outgoing image by one display height and reveal the incoming image from the opposite edge. For rightward switches, move outgoing content upward; for leftward switches, move it downward.

- [ ] **Step 4: Implement safe fallback and cleanup**

If outgoing capture fails, invoke `switchSpace` without an overlay. If destination capture or animation setup fails after switching, remove the cover and finish without reversing the switch. On Screen Recording authorization failure, return a distinguishable error for the app layer to explain and provide a route to Screen Recording settings. Always remove the overlay after success, cancellation, or error.

- [ ] **Step 5: Test coordinator behavior with injected capture results**

In `SpaceTransitionOverlayTests.swift`, test successful sequencing, a `canSwitch` closure returning false (no capture and no switch), denied permission, outgoing capture failure, destination capture failure, and a switch closure returning false. Assert the switch closure is invoked once where appropriate and the overlay is cleaned up in every path. Run: `swift test --filter SpaceTransitionOverlayTests`. Expected: PASS.

### Task 3: Route app-initiated switches through the overlay

**Files:**
- Modify: `Sources/InstantSpaceSwitcher/Core/AppDelegate.swift`
- Create: `Sources/InstantSpaceSwitcher/Core/SpaceSwitchRequestQueue.swift`
- Create: `Sources/InstantSpaceSwitcher/UI/ScreenRecordingPermissionAlert.swift`
- Test: `Tests/ISSTests/SpaceSwitchRequestQueueTests.swift`

**Interfaces:**
- Consumes: `SpaceTransitionOverlay.transition(direction:duration:canSwitch:switchSpace:)` and `SpaceTransitionSettings.duration(forGestureSpeed:)`.
- Produces: `@MainActor final class SpaceSwitchRequestQueue` with `func enqueue(_ operation: @escaping () async -> Void)`.
- Preserve the existing C switch API and callback. Keep the OSD callback separate from overlay lifecycle.

- [ ] **Step 1: Route left/right and direct-index app switches through one async coordinator**

Route keyboard shortcut requests, including left/right, direct-index, and last-space shortcuts, through the coordinator. Keep the existing app menu and direct menu-selection paths unchanged. Keep C bounds checks as the authority for whether a switch succeeds, and preserve the existing beep on blocked or failed switches. Do not change native physical trackpad behavior or swipe-override interception.

- [ ] **Step 2: Serialize requests while a transition is active**

Use `SpaceSwitchRequestQueue.enqueue(_:)` to serialize keyboard switch requests in arrival order so rapid shortcuts do not overlap windows or lose a switch. Add tests proving enqueued async operations do not overlap and complete in arrival order. Supply a `canSwitch` preflight using `iss_get_space_info` and `iss_can_move` for directional shortcuts, and skip same-space direct-index requests; if space info is unavailable, allow the C switch call to remain authoritative.

- [ ] **Step 3: Connect the existing Animation Speed preference**

Read `gestureSpeed` from `UserDefaults` when each request starts and pass its mapped duration to the coordinator. Keep current preset labels and the native gesture-speed behavior for the underlying switch.

- [ ] **Step 4: Explain Screen Recording permission failure**

Implement the permission explanation in `ScreenRecordingPermissionAlert.swift`. Present it non-blocking and once per app run when capture authorization is denied. Include an action that opens the macOS Screen Recording settings page and leave switching functional without the overlay. Do not request permission until a keyboard-initiated animated switch needs a capture.

- [ ] **Step 5: Verify the app target builds and tests pass**

Run: `swift test`
Expected: PASS, including the new settings/coordinator tests and existing ISS tests.

### Task 4: Document permission and manually verify the animation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the optional Screen Recording permission**

Explain that Screen Recording permission is used only to snapshot the active display for the custom transition, that protected content may be omitted, and that space switching still works without permission but falls back to the normal macOS transition.

- [ ] **Step 2: Build the app**

Run: `swift build`
Expected: PASS for the app, C library, and CLI targets on macOS 13+ SDK.

- [ ] **Step 3: Manually verify supported runtime behavior**

On macOS, grant Screen Recording permission and verify left/right hotkeys and direct-index shortcuts show vertical slides, the selected destination is correct, the OSD remains unchanged, and each Animation Speed preset affects slide duration (with “Instant” showing no overlay animation). Revoke permission and verify the app still switches spaces and explains the fallback.
