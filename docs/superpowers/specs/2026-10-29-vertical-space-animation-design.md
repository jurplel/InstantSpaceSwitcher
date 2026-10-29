# Vertical Space Animation Design

## Intent

Replace the native horizontal space-switch animation with a customizable
vertical slide when a keyboard shortcut changes spaces. The app should still
select the adjacent space to the left or right as before.

## Goals

- Show a vertical transition for keyboard-initiated space switches.
- Animate snapshots of the outgoing and incoming desktops so the transition
  visually includes their windows.
- Use the existing Animation Speed preference to set the overlay duration.
- Keep current hotkey behavior and space bounds checks.

## Non-goals

- Change space ordering or convert left/right hotkeys to up/down navigation.
- Customize colors, easing curves, or other animation parameters in settings.
- Replace or redesign the existing OSD.

## Constraints

- Space changes are currently issued in `Sources/ISS/ISS.c` through synthetic
  Dock swipe events. The app's switch callback is used to update the OSD.
- Snapshot overlays require Screen Recording permission. Protected or
  non-capturable content may not appear in the snapshots.
- The app currently requests Accessibility permission but has no
  ScreenCaptureKit integration or Screen Recording permission flow.
- The package supports macOS 13 and later.

## Approaches

1. **Snapshot overlay (chosen):** Capture the outgoing and incoming desktop
   images, cover the native switch, and animate the snapshots vertically. This
   provides a customizable transition that visually includes desktop windows,
   at the cost of a new Screen Recording permission and capture edge cases.
2. **Abstract overlay:** Animate a designed panel or gradient over the space
   switch without capturing the desktops. It avoids Screen Recording
   permission but does not make the real windows appear to slide.
3. **Vertical native swipe:** Change the synthetic gesture axis and rely on
   macOS's built-in transition. It does not provide the customization requested
   and may be interpreted as another system gesture rather than changing spaces.

The user chose the snapshot overlay, specifically to enable more customization
than the native macOS animation. The user also chose to reuse the existing
Animation Speed preference for overlay duration.

## Behavior

- Left/right hotkeys continue selecting the previous/next space.
- The native desktop switch should happen underneath an opaque snapshot layer
  so the native transition is not visible.
- The overlay animates the outgoing desktop upward or downward and reveals the
  destination snapshot from the opposite edge. The direction should correspond
  consistently to the existing left/right switch direction; the exact mapping
  is an implementation detail.
- Overlay duration should derive from the existing Animation Speed selection.
- If capture or overlay setup fails, complete the regular space switch without
  blocking the hotkey; surface the failure through the repository's existing
  logging/error conventions.
- The existing OSD remains independent and retains its current settings.

## Decisions left to the builder

- Choose the macOS capture and overlay APIs that work on macOS 13+, exclude the
  app's own overlay from capture, and avoid capturing unrelated displays.
- Coordinate capture, native switching, and destination capture so the
  transition is seamless, including rapid consecutive shortcuts.
- Handle Screen Recording permission denial or revocation gracefully and
  provide a clear permission explanation/route in the app.
- Preserve existing speed preset labels and use their values to derive a
  sensible overlay duration; do not add new animation controls.
- Add focused tests for duration mapping and transition direction/state where
  practical, and validate remaining behavior manually on macOS.
