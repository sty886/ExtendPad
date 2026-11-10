import Foundation

/// Pure gating logic for whether a USB media session may be constructed at
/// all — kept free of TrustStore/Keychain/Network types so it is directly
/// unit-testable. USB is only a route: this is the one place that decides
/// whether a physically-attached, usbmux-reachable device also has the
/// cryptographic identity required before any media transport is built (see
/// `MacSender.SenderTransport.usb`, which cannot even be constructed without
/// a `TLSSessionConfig`). A udid with no known peer identity, or a known
/// identity with no matching pin, resolves to `nil` — never a self-reported
/// or best-effort identity.
enum USBSecureTransportPolicy {
    struct Resolved: Equatable {
        let peerID: String
        let pin: Data
    }

    /// - installIDByUDID: the Mac's learned udid -> peerID mapping (from a
    ///   prior hello or pairing ceremony — never self-reported at dial time).
    /// - pin: looks up the current TrustStore pin for a peerID.
    static func resolve(udid: String, installIDByUDID: [String: String],
                         pin: (String) -> Data?) -> Resolved? {
        guard let peerID = installIDByUDID[udid], let pinData = pin(peerID) else { return nil }
        return Resolved(peerID: peerID, pin: pinData)
    }

    /// The UDID to offer/dial for [peerID], and only while that device is
    /// attached right now. The persisted mapping outlives the cable: dialing it
    /// after the device is gone fails with "adb: device not found" and, worse,
    /// the doomed session owns the peer so the routes that would work are
    /// skipped. Among several attached UDIDs the lowest serial is deterministic.
    static func attachedUDID(peerID: String, installIDByUDID: [String: String],
                             attachedUDIDs: Set<String>) -> String? {
        installIDByUDID
            .filter { $0.value == peerID && attachedUDIDs.contains($0.key) }
            .keys.sorted().first
    }
}
