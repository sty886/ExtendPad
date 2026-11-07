# ExtendPad setup guide

ExtendPad uses a Mac as the sender and supports Android devices and other
Macs as receivers. See [README.md](../README.md) for the current feature
overview and [PARITY.md](PARITY.md) for platform differences.

## Requirements

- Mac sender: macOS 14 or later.
- Standalone Mac receiver: macOS 12 or later.
- Android receiver: Android 10 or later.
- Mac builds: the Xcode version in `.xcode-version` and XcodeGen.
- Android builds: JDK 17 and the Android SDK.

## Generate and build the Mac apps

`project.yml` is the tracked XcodeGen specification. The `.xcodeproj` is
generated locally and must not be edited directly.

```sh
./generate.sh
xcodebuild -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath build/macos build
```

Build the standalone receiver with:

```sh
xcodebuild -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMacReceiver \
  -configuration Debug \
  -derivedDataPath build/mac-receiver build
```

For signed local builds, create `.env` with `DEVELOPMENT_TEAM=YOURTEAMID`
before running `generate.sh`. Never commit signing keys, profiles or `.env`.

### Building without a provisioning profile

The Mac app's `TrustStore` uses the data-protection Keychain, which needs a
provisioning profile (the `keychain-access-groups` entitlement). On a Mac
with no Apple Developer account signed into Xcode, the normal build still
launches but cannot create its identity: `SecItemAdd` fails with
`-34018` (`errSecMissingEntitlement`), so the Mac never advertises
`_opendisplay-mac-pair._tcp`, USB discovery answers "host unavailable", and
receivers keep showing "Looking for hosts…".

Build the login-keychain variant for that case:

```sh
xcodebuild -project ExtendPad.xcodeproj -scheme OpenSidecarMac \
  -configuration Release -derivedDataPath build/macos-local \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=LOCAL_FILE_KEYCHAIN \
  CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO build

codesign --force --deep --sign "Apple Development: <your identity>" \
  build/macos-local/Build/Products/Release/ExtendPad.app
```

It stores its identity, pins and trust in the login keychain under the
`.local` Keychain namespaces instead of the data-protection Keychain. That is
a separate identity from a profile-signed build, so receivers pair with it
once, separately.

## Build and install Android

From the repository root:

```sh
cd apps/android
./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The Debug app uses a separate application ID and can coexist with a release
installation. See [the Android README](../apps/android/README.md) for test,
emulator and signing commands.

## Permissions

| Where | Permission | Purpose |
| --- | --- | --- |
| Sending Mac | Screen Recording | Capture Mirror, Extend and Window content |
| Sending Mac | Accessibility | Inject approved touch, pointer and keyboard input |
| Sending Mac | Local Network | Discover and connect over Wi-Fi |
| Android | USB debugging, only for USB | Authorize the opaque ADB tunnel |

Connecting does not grant input. Enable Allow Input on the Mac and approve
the receiver's Request Control for the current session.

## Connect over Wi-Fi

1. Open the receiver and Mac app on the same network.
2. Allow local-network access and firewall access where requested.
3. On the receiver, select the Mac and choose **Wi-Fi**.
4. Confirm the matching pairing code on both devices.
5. Choose Mirror, Extend or Windows.

The receiver lists every running Mac it discovers with Bonjour; no IP address
is needed. Discovery never selects a route or starts a session by itself.

## Connect Android over USB

1. Install Android SDK platform-tools so `adb` is available.
2. Enable Developer options and USB debugging on the Android device.
3. Connect a data-capable cable, unlock the device and authorize this Mac.
4. Install and open the Android app.
5. Pair and connect normally.

ExtendPad uses authorized ADB forwarding only as an opaque byte tunnel.
Pairing, pinned identities and encrypted transport remain mandatory. Only
one authorized Android USB device is supported at a time because the host
ports cannot be mapped independently to multiple devices.

The Android app also declares an AOA (Android Open Accessory) control
channel, which avoids platform-tools and developer options on devices whose
firmware completes the accessory switch. The shipping Mac transport still
uses ADB because the tested Huawei firmware accepts AOA's GET_PROTOCOL and
ACCESSORY_START but never re-enumerates as an accessory; see
[TECHNICAL_NOTES.md](TECHNICAL_NOTES.md#usb-transport-aoa-versus-the-adb-tunnel-2026-11-07).

## Mac-to-Mac connections

Mac Receiver uses network routes, including supported wired networking.
Install the main app or standalone receiver on the receiving Mac, open it,
and pair it with the sender. Keyboard and trackpad forwarding requires the
same per-session control grant as other input.

## Remote Access

Remote Access uses a reachable private-network address, such as a Tailscale
endpoint. It does not provide a hosted relay or replace pairing.

1. Configure the same private network on both devices.
2. Add the Mac's address in the receiver's Remote settings.
3. Pair over Remote or use the saved address for an already paired Mac.
4. Connect. The sending Mac authenticates and dials the receiver.

Wake & Connect is limited by hardware, Wake for Network Access and network
conditions. See [REMOTE_WAKE_ON_LAN.md](REMOTE_WAKE_ON_LAN.md).

## Display and input

- **Mirror** copies an active physical display.
- **Extend** creates a separate virtual display.
- **Windows** shows selected Mac windows as tiles without closing them when a
  tile is removed.
- **Audio** is enabled by the receiver; A/V Sync and Resync adjust playback.
- **Input** remains View Only until the Mac grants control for the session.
- **Pause** stops both media interaction and remote input until resumed.

See [WINDOW_MODE.md](WINDOW_MODE.md) and
[RECEIVER_CONTROLS.md](RECEIVER_CONTROLS.md).

## Troubleshooting

- **No nearby receiver:** confirm both devices are open, on the same network,
  and permitted to use local networking.
- **No picture:** check Screen Recording permission and whether the selected
  Mirror source is active.
- **Extend is unavailable:** enable video capture and check virtual-display
  errors on the sending Mac.
- **Input does nothing:** check Accessibility, Allow Input and the current
  session's control grant.
- **Android USB is unavailable:** confirm `adb devices` lists exactly one
  authorized `device`, not `offline` or `unauthorized`.
- **Remote Access fails:** verify the private network, saved address and that
  the Mac can reach the receiver as well as the receiver reaching the Mac.
- **Logs:** use the Mac app's Logs action, or Android Settings & Help →
  Diagnostics. Redact private addresses and content before sharing.

## Tests

```sh
xcodebuild test \
  -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

cd apps/android
./gradlew :core:test :app:testDebugUnitTest
```

Automated tests do not replace physical display, input, audio, USB and
network validation. Record what was actually tested.
