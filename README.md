<div align="center">

<img src="assets/readme/website/mark.png" alt="ExtendPad logo" width="128">

# ExtendPad

**Use Android or another Mac as an additional display for your Mac.**

Mirror or extend the desktop, arrange individual Mac windows, and control the
Mac with touch, trackpad, mouse and keyboard input. Connections use local
Wi-Fi, an authorized Android USB tunnel, or a private network you control.

**English** · [简体中文](README.zh-CN.md)

[Setup](docs/SETUP.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Security](SECURITY.md) · [Support](SUPPORT.md)

</div>

## Supported platforms

| Role | Platform |
| --- | --- |
| Share and receive | Mac with macOS 14 or later |
| Receiver only | Mac with macOS 12 or later |
| Receiver | Android 10 or later |

ExtendPad does not provide a Windows or Linux sender. The Mac is always the
video/audio sender.

## Features

- **Mirror:** stream an existing physical Mac display.
- **Extend:** create a separate virtual display and arrange it in macOS.
- **Windows:** show selected Mac windows as independently arranged tiles.
- **Input:** direct touch, trackpad-style control, keyboard, mouse and common
  Mac gestures, subject to the Mac owner's per-session permission.
- **Controls:** customizable trays, shortcuts, profiles and adaptive layouts
  on Android phones, tablets and foldables.
- **Files and clipboard:** owner-approved Remote Finder access and optional
  Unified Clipboard on Android.
- **Audio:** stream Mac system audio with adjustable A/V synchronization.
- **Connections:** local Wi-Fi, Android USB through an authorized ADB tunnel,
  and Remote Access through a private network such as Tailscale.
- **Security:** explicit pairing, pinned peer identities and encrypted
  sessions without a hosted relay.

See [PARITY.md](docs/PARITY.md) for platform differences and verification
limits.

## Build from source

### Mac

Install the Xcode version in `.xcode-version` and XcodeGen, then run:

```sh
./generate.sh
xcodebuild -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath build/macos build
```

For local signing, set `DEVELOPMENT_TEAM` in `.env` before generating. Open
`ExtendPad.xcodeproj` to run the main app or the `OpenSidecarMacReceiver`
scheme. `project.yml` is the source of truth; do not edit the generated
project.

### Android

Install JDK 17 and the Android SDK, then run:

```sh
cd apps/android
./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

See [apps/android/README.md](apps/android/README.md) for USB setup, tests and
release options.

## Connect

1. Open ExtendPad on the Mac and the Android device or receiving Mac.
2. Use local Wi-Fi, Android USB, or a configured private-network route.
3. Confirm the same pairing code on both devices.
4. Choose Mirror, Extend or Windows.
5. Grant Screen Recording on the sending Mac. For remote control, also grant
   Accessibility, enable Allow Input, and approve the receiver's request.

Android USB requires Android SDK platform-tools, USB debugging and an
authorized connection. ADB transports opaque encrypted bytes only; it does
not replace pairing or inject input.

## Repository layout

- `apps/android/` — Android app and Kotlin core module
- `apps/macos/` — Mac sender and unified Mac app
- `apps/macos-receiver/` — standalone Mac receiver
- `packages/shared/` — shared Swift protocol and receiver logic
- `tests/macos/` — Mac unit and integration tests
- `fixtures/` — cross-language test vectors
- `assets/` — brand and documentation resources
- `docs/` — setup, architecture, protocol and release documentation
- `src/`, `public/`, `tools/` — project website

## Documentation

- [Setup and troubleshooting](docs/SETUP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Protocol](docs/PROTOCOL.md) and [compatibility](docs/COMPATIBILITY.md)
- [Window mode](docs/WINDOW_MODE.md)
- [Receiver controls](docs/RECEIVER_CONTROLS.md)
- [Security model](SECURITY.md)
- [Contribution guide](CONTRIBUTING.md)
- [Release process](docs/RELEASE.md)

## Contributing and license

Contributions and device-compatibility reports are welcome. Base development
branches on `dev` and follow [CONTRIBUTING.md](CONTRIBUTING.md). Report
security vulnerabilities privately through GitHub's vulnerability-reporting
flow.

ExtendPad is licensed under [GPL-3.0](LICENSE). It incorporates OpenDisplay
work by Philip Poloczek and retains its attribution and license obligations.
Use it only with devices you own or are authorized to access.
