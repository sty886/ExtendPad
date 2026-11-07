# ExtendPad for Android

ExtendPad for Android is a receiver for a Mac sender. It supports Android 10
or later on phones, tablets and foldables.

## Build

Requires JDK 17 and the Android SDK.

```sh
./gradlew :core:test
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleDebug
./gradlew :app:lintRelease :app:bundleRelease
```

The Debug APK is written to
`app/build/outputs/apk/debug/app-debug.apk` and uses the application ID suffix
`.debug`.

Install it on one connected, authorized device:

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Connect

### USB

Install Android SDK platform-tools, enable USB debugging, connect a
data-capable cable and authorize the Mac. ExtendPad uses `adb forward` for the
media and pairing ports, plus `adb reverse` on TCP 9005 so the Android app can
list the Mac's USB availability. The Android user explicitly selects the Mac
and USB or Wi-Fi; discovery does not connect or switch routes automatically.
ADB is only an opaque tunnel: pairing, mutual TLS and pinned peer identities
remain required, and ADB is not used to inject input.

Only one authorized Android USB device is supported at a time because the
host ports cannot be mapped independently to multiple devices.

### Local network and Remote Access

On local Wi-Fi, open the Mac and Android apps and pair the discovered devices.
For a remote network, configure a reachable private-network route such as
Tailscale. The address is a routing hint; it never replaces authentication.

## Modules

- `core/`: plain Kotlin/JVM protocol, pairing, pinned TLS, framing, media,
  controls, workspace and clipboard logic.
- `app/`: Android Keystore, DNS-SD, MediaCodec, Compose UI, input and device
  integration.

Cross-language fixtures live under `../../fixtures/` from this directory.
Mac tests that generate them are in `tests/macos/`.

## Tests

```sh
./gradlew :core:test :app:testDebugUnitTest
```

With one supported emulator booted and the Debug app installed:

```sh
MEOW_EMULATOR_SERIAL=emulator-5554 MEOW_EMULATOR_PROFILE=phone \
  MEOW_SMOKE_SHOTS=/path/to/shots \
  ./gradlew :core:test --tests '*EmulatorSmokeTest' --rerun
```

`MEOW_EMULATOR_PROFILE` accepts `phone`, `tablet` or `foldable`.

Release builds accept `-Pmeow.versionCode=…` and
`-Pmeow.versionName=…`. Upload signing is enabled only when the CI signing
environment supplies the upload key; otherwise release bundles are unsigned.

See [RECEIVER_CONTROLS.md](RECEIVER_CONTROLS.md) for controls and physical QA,
and [../../docs/PARITY.md](../../docs/PARITY.md) for platform differences.
Building and unit testing do not establish physical-device compatibility.
