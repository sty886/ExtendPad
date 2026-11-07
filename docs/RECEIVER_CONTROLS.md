# Receiver controls

ExtendPad receivers support View Only by default and require a per-session
Mac owner grant before sending input.

## Android

Android provides Direct Touch and Trackpad modes, customizable control and
function trays, profiles, chords, keyboard/mouse input and adaptive layouts
for phones, tablets and foldables. Local zoom and pan do not require input
permission. See [../apps/android/RECEIVER_CONTROLS.md](../apps/android/RECEIVER_CONTROLS.md).

## Mac Receiver

Mac Receiver forwards keyboard and trackpad events while its video window is
active and the sending Mac has granted control. It uses the same shared
session, input and revocation rules as Android. Input is not captured
globally.

## Common rules

- Connecting and controlling are separate permissions.
- Every connection begins without an input grant.
- Pause, revocation, Forget and connection replacement stop input and release
  held keys, buttons and gestures.
- Receiver-local layout and viewport state stays on the receiver.
- The Mac decides which display or window receives approved input.

Implementation details live in `packages/shared/`,
`apps/android/core/src/main/kotlin/`, and
`apps/macos-receiver/ReceiverInputForwarding.swift`.
