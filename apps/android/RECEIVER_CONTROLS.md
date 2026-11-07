# Android receiver controls

## Layouts

The receiver adapts to its usable window rather than assuming a fixed device
shape. Compact windows use trays; large windows can use strip, overlay and
custom radial layouts. Fold and hinge regions, display cutouts and the
on-screen keyboard reserve space without changing the Mac session merely
because the window was resized.

Profiles, tray items, chord palettes and custom actions are stored locally.
Custom layouts can be exported and imported as share codes.

## Input authorization

Every input message passes through the authenticated session's input gate.
A new connection starts View Only. Request Control asks the Mac owner for a
per-session grant; pausing, revoking, forgetting or replacing the connection
releases held input. Local view navigation does not require Mac input
permission and never injects events.

## Input modes

- **Direct Touch** maps touch positions to the remote display. It starts in
  **Natural Touch** (schema 23): one finger scrolls, pressing and then moving
  drags, and a long press right-clicks. Classic (the finger is the pointer)
  and Smart Touch remain available in Settings → Input.
- **Trackpad** moves the pointer relatively.
- Scrolling, dragging, clicking, multi-touch gestures, keyboard and supported
  mouse/stylus events use the shared protocol.
- Control trays provide modifiers, keyboard access, settings and customizable
  shortcuts.

## Verification

Host tests cover the protocol and control logic. Emulator smoke tests can
cover pairing, decoding, input grants, typing, rotation, fold/unfold and
reconnect when configured as described in [README.md](README.md).

Physical QA should still cover:

1. USB and Wi-Fi pairing, connection and reconnection.
2. Direct Touch, Trackpad, scrolling, dragging and multi-touch gestures.
3. Software and hardware keyboards, including held keys and modifiers.
4. Control trays, custom layouts, folding, rotation and split-screen resizing.
5. Audio, A/V Sync, Picture in Picture and performance overlays.
6. Input revocation, pause, backgrounding and ensuring no input stays held.
7. Accessibility services and the target device's stylus, mouse and keyboard.

Do not record physical checks as passed unless they were actually run.
