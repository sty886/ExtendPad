# Android USB availability evidence (2026-11-08)

Captured from the Android Debug app on the same emulator (`Medium_Phone_API_36.1`,
1080×2400, Chinese UI), so each pair is directly comparable. The "Mac" is a
stand-in for the `USBHostDiscoveryWire` v1 discovery socket (127.0.0.1:9005,
reached through `adb reverse tcp:9005 tcp:9005`), not a real Mac.

| File | Revision | Scenario |
| --- | --- | --- |
| `before-1-usb-available.png` | base `06b092f` | A USB host answers discovery; the host row offers USB. |
| `before-2-usb-stale.png` | base `06b092f` | The same screen 8 s after that host stops answering: the dead "USB 可用" row is still offered. |
| `after-1-usb-available.png` | this branch | The same host answers discovery. |
| `after-2-usb-withdrawn.png` | this branch | The same screen 8 s after the host stops answering: the stale row is withdrawn. |
| `before-3-usb-error-english.png` | base `06b092f` | "Pair via USB" while the request gets no answer shows an English dialog. |
| `after-3-usb-error-chinese.png` | this branch | The same failure in the Chinese UI. |

Both captures used a cleared app data set and the same fake host script; the
time difference in the status bar is the test run duration, not a UI change.
No real device names, addresses, keys or pairing codes appear in the images.
