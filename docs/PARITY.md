# Receiver feature parity

ExtendPad supports Android and Mac receivers connected to a Mac sender.
Implementation does not imply physical verification on every device or OS
version.

**Yes** = implemented · **Partial** = implemented with the noted limitation ·
**No** = not implemented · **—** = not applicable.

## Connections

| Feature | Android | Mac Receiver |
| --- | --- | --- |
| Pairing with a matching code | Yes | Yes |
| Local Wi-Fi/Bonjour discovery | Yes | Yes |
| Receiver-initiated Connect, with the Mac dialing | Yes | Yes |
| USB | Yes, authorized ADB tunnel (AOA path staged; some OEM firmware does not switch) | Network routes, including wired networking |
| Remote Access through a private network | Yes | Yes |
| Per-session connection approval | Yes | Yes |
| Auto-Reconnect | Yes | Yes |
| Wake & Connect | Yes, subject to network/hardware limits | Yes, subject to network/hardware limits |

## Display and audio

| Feature | Android | Mac Receiver |
| --- | --- | --- |
| Mirror and Extend | Yes | Yes |
| Window mode and up to nine tiles | Yes, subject to available space | Yes, subject to available space |
| Tile arrangement, rotation and switching | Yes | Yes |
| Foldable/hinge-aware layouts | Yes | — |
| Streaming profile, frame rate and display requests | Yes, capability-gated | Yes, capability-gated |
| Mac system audio | Yes | Yes |
| A/V Sync and Resync | Yes | Yes |
| Picture in Picture | Yes | — |
| Performance overlay | Yes | Yes |

## Input and controls

| Feature | Android | Mac Receiver |
| --- | --- | --- |
| Direct Touch and Trackpad modes | Yes | Trackpad/mouse |
| Keyboard input | Yes | Yes |
| Per-session Request Control | Yes | Yes |
| Common Mac system gestures | Yes | Partial, through supported input events |
| Customizable control trays and profiles | Yes | — |
| Adaptive phone/tablet/foldable controls | Yes | — |
| Hardware keyboard/mouse | Partial; device-dependent | Yes |
| Stylus input | Partial; device-dependent | — |

## Files, clipboard and diagnostics

| Feature | Android | Mac Receiver |
| --- | --- | --- |
| Remote Finder browsing and previews | Yes, with Mac owner permission | No |
| Remote Finder uploads and file operations | Yes, with the matching permission | No |
| Unified Clipboard | Yes, opt-in on both sides | No |
| Connection diagnostics | Yes | Yes |

## Verification limits

- Mac-to-Mac keyboard/trackpad forwarding has automated coverage, but
  physical two-Mac verification remains limited.
- Android unit and emulator coverage does not establish every physical
  device's touch, stylus, audio, keyboard, foldable or OEM behavior.
- USB requires an authorized ADB connection and currently supports one
  Android device at a time.
- No Windows or Linux sender is provided.

See [SETUP.md](SETUP.md) for setup and
[RECEIVER_CONTROLS.md](RECEIVER_CONTROLS.md) for control behavior.
