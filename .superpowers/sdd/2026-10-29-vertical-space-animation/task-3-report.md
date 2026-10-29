# Task 3 report: Keyboard shortcut transition integration

## Implementation

- Added `SpaceSwitchRequestQueue`, a main-actor FIFO that awaits each asynchronous operation before starting the next. This keeps rapid keyboard shortcuts serialized across capture, switch notification, animation, and cleanup.
- Routed hotkey left/right and direct-index/last-space requests through `SpaceTransitionOverlay`; menu-bar directional delegates and direct menu selection remain on their previous synchronous C switch routes.
- Directional requests preflight with `iss_get_space_info` and `iss_can_move`. If space info is unavailable, the C switch call is still invoked. Direct-index requests skip same-space work; all actual switch success, failure, and bounds behavior remain determined by the existing C APIs.
- Read `gestureSpeed` from `UserDefaults` when each queued keyboard request begins and mapped it with `SpaceTransitionSettings.duration(forGestureSpeed:)`. The native gesture speed setup and OSD C callback remain unchanged and independent of the overlay.
- Added `ScreenRecordingPermissionAlert`, a non-blocking, non-activating panel shown at most once per app run after a denied capture. Its settings button opens the Screen Recording privacy pane. The existing overlay capture path only preflights authorization when a keyboard transition attempts a capture; its fallback still performs the switch without the overlay.
- Added `SpaceSwitchRequestQueueTests.testEnqueuedOperationsRunInArrivalOrderWithoutOverlapping`, asserting operation order and a maximum of one active operation.

## Validation

- `swift build` — **PASS**.
- `swiftc -parse Tests/ISSTests/SpaceSwitchRequestQueueTests.swift` — **PASS** (syntax check).
- `git diff --check` — **PASS**.
- `swift test --filter SpaceSwitchRequestQueueTests` — **BLOCKED** before tests can run because the selected Command Line Tools do not provide the `XCTest` module (`no such module 'XCTest'`).
- `swift test` — **BLOCKED** for the same environment issue.

The app target builds successfully. Test execution requires a full Xcode developer directory with XCTest available.
