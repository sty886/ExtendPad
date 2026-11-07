# ExtendPad upstream attribution

ExtendPad is a customized derivative of **MeowDisplay 2.0**, itself based on **OpenDisplay**.

- MeowDisplay: https://github.com/raiseCatError/meowdisplay
- OpenDisplay: https://github.com/peetzweg/opendisplay
- Integrated MeowDisplay revision: `4e41c135c13b9f872e1a9e39aa5699129ec4a59c` (2026-11-03)

The original copyright notices, author attribution, protocol service names and compatibility identifiers are retained. ExtendPad is distributed under the same **GNU General Public License, version 3**; see `LICENSE`. This notice does not replace or narrow any upstream license or notice.

ExtendPad-specific changes include the product name and bundle identities, an extended-display default for new installations, Android receiver packaging, an authorized-ADB USB tunnel for one Android device, simplified-Chinese interfaces on Mac and Android, Xcode 26.5 build fixes, and disabling upstream MeowDisplay update feeds. The Android USB tunnel retains the existing pairing ceremony, mutual TLS and SPKI pinning; ADB does not inject input or replace application authentication.

The profile-less local Mac package uses a stable development-certificate signature without restricted entitlements. Its `LOCAL_FILE_KEYCHAIN` branch stores an isolated ExtendPad identity in the encrypted login keychain, generates the keypair there, and selects identities by exact certificate DER rather than an ignored file-keychain label filter. Normal signed builds retain the original data-protection-keychain path and namespaces. The local package is not Developer ID signed or Apple notarized.

After the simplified-Chinese interface and local-keychain updates, the normal Mac suite passes 2,560 tests with zero failures and two skipped. Android passes 34 unit tests with zero failures. The Android Debug APK was installed and cold-launched on a Huawei MRX-W39; its home, input-settings and connection-help screens were opened and visually checked in Chinese, including the authorized host-to-device `adb forward` USB instructions. The Mac app includes simplified-Chinese resources for the main and integrated receiver interfaces. The fixed-signature Mac build reached the USB pairing-code presentation on two consecutive launches without keychain errors, and retained exactly one local sender identity across the restart. No independent security audit is implied. Completing pairing confirmation, extended-display streaming, touch and keyboard end-to-end validation remains separately required and must not be inferred from build, launch, pairing-presentation, interface or unit-test results.
