// Compiled into BOTH the Mac and iOS targets (see project.yml `sources`).
// Shared but NOT Foundation-only (unlike Protocol.swift): imports CryptoKit,
// Security, X509, SwiftASN1.

import Foundation
import CryptoKit
import Security
import X509
import SwiftASN1

// Local, profile-less macOS packages cannot use the data-protection keychain:
// its restricted entitlement requires a provisioning profile. Keep the normal
// builds unchanged, but let the explicitly labelled local-package build use
// the user's encrypted login keychain and isolated `.local` namespaces instead.
// Mutual TLS, SPKI pinning and peer-authorization policy remain the same.
private func extendPadKeychainQuery(_ query: [CFString: Any]) -> CFDictionary {
    #if LOCAL_FILE_KEYCHAIN
    var local = query
    local.removeValue(forKey: kSecUseDataProtectionKeychain)
    local.removeValue(forKey: kSecAttrAccessible)
    var keychain: SecKeychain?
    if SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain {
        local[kSecUseKeychain] = keychain
    }
    return local as CFDictionary
    #else
    return query as CFDictionary
    #endif
}

/// Own TLS identity + per-peer SPKI pin store. Shared by both targets.
///
/// Normal builds use the data-protection keychain (TN3137) under the original
/// `WireCrypto.*` namespaces; `LOCAL_FILE_KEYCHAIN` uses isolated login-
/// keychain namespaces. Thread-safe: every public method is internally
/// synchronized (private `NSLock`s); `allPinnedPeerSPKIs()` reads ONLY the
/// in-memory snapshot (no Keychain I/O) so it is safe to call from a TLS
/// verify block.
///
/// Runtime caveat (not a compile-time concern): on macOS, the data-protection
/// keychain requires the app to be signed with an application identifier
/// (TN3137). Normal team-signed Debug/Release builds are fine; a fully
/// unsigned build (`DEVELOPMENT_TEAM` unset, as in CI) will get
/// `errSecMissingEntitlement` at runtime. Every method below fails soft
/// (nil / false / empty, logged) in that case — never crashes.
/// `@unchecked Sendable`: the only mutable stored property is `pinState`.
/// Every read (`allPinnedPeerSPKIs`, `peerID(forSPKI:)`) and write
/// (`refreshSnapshot`, `finishPinMutation`) of it is bracketed by
/// `snapshotLock.lock()` / `snapshotLock.unlock()`, never held across
/// Keychain I/O, and both reads copy out value types (`[Data]`, `String?`),
/// so nothing protected escapes the lock. `pinWriteLock` protects no stored
/// state: it serializes Keychain pin mutations (`setPin`, `forget`,
/// `purgeAll`) against each other, each through its snapshot commit, while
/// `PinSnapshotState`'s revision stops an older lock-free refresh read from
/// overwriting a newer mutation's commit. All Keychain-facing identity
/// helpers (`queryIdentity`, `queryInstallID`, `generateAndStoreIdentity`,
/// `deletePartialIdentityItems`, `spkiFromCertificate`) touch only local
/// state and the Keychain APIs — never `pinState` — so their
/// `identityLock`-held contract (documented at each call site) exists only
/// to serialize Keychain generation, not to protect additional shared state.
/// Lock order: `pinWriteLock` → `snapshotLock`; `identityLock` is never held
/// together with either. All three locks and `shared` are `let`s; `shared`'s
/// one-time initialization is guaranteed by Swift's `static let` semantics.
final class TrustStore: PeerTrustStoring, @unchecked Sendable {
    /// Which Keychain items a store owns. Each namespace is a complete,
    /// independent identity + pin set: nothing pinned in one authorizes a
    /// peer in another.
    struct Namespace: Equatable, Sendable {
        let identityLabel: String
        let pinService: String

        /// Normal signed builds retain the original names and every existing
        /// install's identity and pins. A profile-less local package uses an
        /// isolated file-keychain namespace, never the signed app's identities.
        #if LOCAL_FILE_KEYCHAIN
        static let standard = Namespace(identityLabel: WireCrypto.identityKeychainLabel + ".local",
                                        pinService: WireCrypto.pinKeychainService + ".local")
        static let macReceiverRole = Namespace(identityLabel: WireCrypto.identityKeychainLabel + ".receiver.local",
                                               pinService: WireCrypto.pinKeychainService + ".receiver.local")
        #else
        static let standard = Namespace(identityLabel: WireCrypto.identityKeychainLabel,
                                        pinService: WireCrypto.pinKeychainService)
        static let macReceiverRole = Namespace(identityLabel: WireCrypto.identityKeychainLabel + ".receiver",
                                               pinService: WireCrypto.pinKeychainService + ".receiver")
        #endif
    }

    /// The sender's (and the iPhone/iPad app's) store: unchanged names, so
    /// existing identities and pins are found exactly as before.
    static let shared = TrustStore(namespace: .standard)

    /// The store the receiver role uses (`StreamReceiver`, its pairing and
    /// QUIC listener, receiver settings). The same object as `shared` in
    /// every app except one that declares `MeowDisplayReceiverRoleTrust` =
    /// `separate` in its Info.plist (the unified Mac app), where the receiver
    /// role gets its own namespace. Read once, from the bundle, so it can't
    /// change while anything holds keys from it.
    static let receiverRole: TrustStore = ReceiverRoleConfiguration.separateTrust
        ? TrustStore(namespace: .macReceiverRole) : shared

    let namespace: Namespace

    /// Serializes own-identity lookup + generation (`ownIdentity`,
    /// `installID`). Held across Keychain I/O.
    private let identityLock = NSLock()
    /// Serializes Keychain pin mutations. Held across Keychain I/O, so the
    /// TLS verify path never takes it.
    private let pinWriteLock = NSLock()
    /// Guards `pinState` only; never held across Keychain I/O.
    private let snapshotLock = NSLock()
    /// In-memory snapshot of all pinned peers as (peerID, SPKI DER) pairs,
    /// plus the revision that orders Keychain reads against mutations.
    /// Refreshed from the Keychain by `refreshSnapshot()` and after every pin
    /// mutation; read lock-only everywhere else, so both the TLS verify block
    /// (SPKI membership) and resolvePeerID (SPKI → peerID) run with zero
    /// Keychain I/O on the queue.
    private var pinState = PinSnapshotState()

    /// Cached (peerID, displayName) rows for the UI. `pinnedPeers()` is
    /// called from view bodies; a synchronous Keychain query there stalled
    /// the main thread on every render. The cache is invalidated by every
    /// pin mutation and by a snapshot refresh; `peersRevision` prevents a
    /// query that raced a mutation from committing stale rows.
    private let peersLock = NSLock()
    private var peersRevision: UInt64 = 0
    private var cachedPeers: [(peerID: String, displayName: String)]?

    private init(namespace: Namespace) {
        self.namespace = namespace
        refreshSnapshot()
    }

    // MARK: - Own identity

    /// Fetch the stored identity, generating and persisting a fresh one on
    /// first call. nil = keychain unusable (logged, never crashes).
    func ownIdentity() -> SecIdentity? {
        identityLock.lock()
        defer { identityLock.unlock() }
        if let existing = queryIdentity() {
            return existing
        }
        return generateAndStoreIdentity()
    }

    /// DER SubjectPublicKeyInfo of our own public key — the exact bytes the
    /// bootstrap exchange sends and the peer pins. Always produced by
    /// CryptoKit's `P256.Signing.PublicKey.derRepresentation` (same-source).
    func ownSPKI() -> Data? {
        guard let identity = ownIdentity() else { return nil }
        var cert: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &cert)
        guard status == errSecSuccess, let cert else {
            Log.info("ERROR: ownSPKI failed to copy certificate from identity (status \(status))")
            return nil
        }
        return spkiFromCertificate(cert)
    }

    /// Keychain-backed install ID, created atomically with the identity and
    /// deleted by `purgeAll()` — id and key live and die together.
    /// The caller's own self-id: the Mac uses it as macInstallID for its wire
    /// identity. Never called on iOS — the phone's wire id is
    /// PhoneReceiver.installID (UserDefaults-backed).
    func installID() -> String? {
        identityLock.lock()
        defer { identityLock.unlock() }
        if let existing = queryInstallID() {
            return existing
        }
        // No identity yet ⇒ nothing generated ⇒ no install ID either. Drive
        // generation through the same path as ownIdentity() so the two never
        // diverge (id+key created together, in the same call).
        guard generateAndStoreIdentity() != nil else { return nil }
        return queryInstallID()
    }

    // MARK: - Peer pins (kSecClassGenericPassword rows)

    func hasPin(peerID: String) -> Bool {
        pin(peerID: peerID) != nil
    }

    /// Pinned SPKI DER for a peer, or nil. Reads the Keychain (cold path).
    func pin(peerID: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecAttrAccount: peerID,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(extendPadKeychainQuery(query), &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound {
                Log.info("ERROR: pin(peerID:) lookup failed (status \(status))")
            }
            return nil
        }
        return data
    }

    /// Persist a new pin, or accept an exact existing match. A changed key is
    /// never overwritten; recovery requires an explicit forget first.
    /// The existing-pin check, delete+add and snapshot commit run as one unit
    /// under `pinWriteLock`, so no other pin mutation interleaves with them.
    @discardableResult
    func setPin(peerID: String, spki: Data, displayName: String,
                allowIdentityChange: Bool) -> Bool {
        pinWriteLock.lock()
        defer { pinWriteLock.unlock() }
        snapshotLock.lock()
        let heldElsewhere = pinState.isHeldByAnotherPeer(peerID, spki: spki)
        snapshotLock.unlock()
        guard !heldElsewhere else {
            Log.info("SECURITY: refused a pin another peer already holds (peer \(peerID))")
            return false
        }
        switch TrustPinPolicy.decision(existing: pin(peerID: peerID), presented: spki) {
        case .match:
            return true
        case .identityChanged where !allowIdentityChange:
            Log.info("SECURITY: refused changed identity for peer \(peerID)")
            return false
        case .identityChanged, .new:
            break
        }
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecAttrAccount: peerID,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemDelete(extendPadKeychainQuery(deleteQuery))

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecAttrAccount: peerID,
            kSecAttrLabel: displayName,
            kSecValueData: spki,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemAdd(extendPadKeychainQuery(addQuery), nil)
        // Read back even when the add failed: the delete above may already
        // have removed the old pin, and the snapshot must not keep it.
        finishPinMutation()
        guard status == errSecSuccess else {
            Log.info("ERROR: setPin failed for peer \(peerID) (status \(status))")
            return false
        }
        return true
    }

    /// Remove one peer's pin and refresh the snapshot.
    func forget(peerID: String) {
        PairedMacUserName.forget(peerID: peerID)
        pinWriteLock.lock()
        defer { pinWriteLock.unlock() }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecAttrAccount: peerID,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemDelete(extendPadKeychainQuery(query))
        if status != errSecSuccess, status != errSecItemNotFound {
            Log.info("ERROR: forget(peerID:) failed for \(peerID) (status \(status))")
        }
        finishPinMutation()
    }

    /// Nuke everything in both namespaces: all pins, identity key+cert,
    /// install-ID row; empty the snapshot. (Reinstall cleanup and
    /// "Reset identity" both land here.)
    func purgeAll() {
        pinWriteLock.lock()
        defer { pinWriteLock.unlock() }
        let deletions: [[CFString: Any]] = [
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: namespace.pinService,
                kSecUseDataProtectionKeychain: true,
            ],
            [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: namespace.identityLabel,
                kSecUseDataProtectionKeychain: true,
            ],
            [
                kSecClass: kSecClassCertificate,
                kSecAttrLabel: namespace.identityLabel,
                kSecUseDataProtectionKeychain: true,
            ],
            [
                kSecClass: kSecClassKey,
                kSecAttrApplicationTag: Data(namespace.identityLabel.utf8),
                kSecUseDataProtectionKeychain: true,
            ],
        ]
        for query in deletions {
            let status = SecItemDelete(extendPadKeychainQuery(query))
            if status != errSecSuccess, status != errSecItemNotFound {
                Log.info("ERROR: purgeAll deletion failed for class \(query[kSecClass] ?? "?") (status \(status))")
            }
        }
        finishPinMutation(purged: true)
    }

    /// When each pinned peer was paired (its Keychain row's creation date), for Clean Up.
    func pinnedPeerDates() -> [String: Date] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain: true,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(extendPadKeychainQuery(query), &out) == errSecSuccess, let items = out as? [[CFString: Any]] else { return [:] }
        return items.reduce(into: [:]) { r, item in
            if let account = item[kSecAttrAccount] as? String, let date = item[kSecAttrCreationDate] as? Date { r[account] = date }
        }
    }

    /// (peerID, displayName) rows for the "Paired Macs"/forget UI
    /// (kSecMatchLimitAll enumeration). Wired to the Settings "Paired Macs"
    /// list.
    ///
    /// The first call reads the Keychain; later calls return the cached rows
    /// until a pin mutation or a snapshot refresh invalidates them. This
    /// keeps view bodies and the network queue from doing Keychain I/O on
    /// every render.
    func pinnedPeers() -> [(peerID: String, displayName: String)] {
        peersLock.lock()
        let revision = peersRevision
        if let cached = cachedPeers {
            peersLock.unlock()
            return cached
        }
        peersLock.unlock()

        let rows = queryPinnedPeers()

        peersLock.lock()
        // A pin mutation that ran while the query was in flight wins.
        if peersRevision == revision { cachedPeers = rows }
        peersLock.unlock()
        return rows
    }

    /// Invalidate the cached `pinnedPeers()` rows. Called after every Keychain
    /// pin mutation and after a full snapshot refresh. Safe to call with
    /// `pinWriteLock` held.
    private func invalidatePeersCache() {
        peersLock.lock()
        peersRevision &+= 1
        cachedPeers = nil
        peersLock.unlock()
    }

    private func queryPinnedPeers() -> [(peerID: String, displayName: String)] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(extendPadKeychainQuery(query), &out)
        guard status == errSecSuccess, let items = out as? [[CFString: Any]] else {
            if status != errSecItemNotFound {
                Log.info("ERROR: pinnedPeers lookup failed (status \(status))")
            }
            return []
        }
        return items.compactMap { item in
            guard let account = item[kSecAttrAccount] as? String else { return nil }
            let label = item[kSecAttrLabel] as? String ?? account
            return (peerID: account, displayName: label)
        }
    }

    // MARK: - In-memory SPKI snapshot

    /// Lock-protected copy of the snapshot. NEVER touches the Keychain —
    /// this is what TLS verify blocks read via the `pinnedSPKIs` closure.
    func allPinnedPeerSPKIs() -> [Data] {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return pinState.allSPKIs
    }

    /// Which pinned peerID owns this leaf SPKI, from the in-memory snapshot
    /// ONLY — no Keychain I/O, so it is safe on the TLS/video queue right after
    /// a handshake (resolvePeerID). nil if the SPKI matches no current pin.
    func peerID(forSPKI spki: Data) -> String? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return pinState.peerID(forSPKI: spki)
    }

    /// Re-read all pins from the Keychain into the snapshot. Called by init;
    /// listeners also call it on start. The read runs with no lock held, so
    /// it is committed only if no pin mutation happened since it began —
    /// otherwise it may predate that mutation's write, and it is dropped:
    /// the mutation commits its own, later read-back.
    func refreshSnapshot() {
        snapshotLock.lock()
        let ticket = pinState.beginRefresh()
        snapshotLock.unlock()
        let fresh = readPinsFromKeychain()
        snapshotLock.lock()
        pinState.commit(fresh, readAt: ticket)
        snapshotLock.unlock()
        invalidatePeersCache()
    }

    /// Tail of every Keychain pin mutation. Must be called with
    /// `pinWriteLock` held and only AFTER the mutation's Keychain writes:
    /// the revision bump invalidates any refresh that may have read the
    /// Keychain before those writes, then this mutation's read-back (empty
    /// after `purgeAll`) commits.
    private func finishPinMutation(purged: Bool = false) {
        snapshotLock.lock()
        let ticket = pinState.keychainDidMutate()
        snapshotLock.unlock()
        let fresh = purged ? [] : readPinsFromKeychain()
        snapshotLock.lock()
        pinState.commit(fresh, readAt: ticket)
        snapshotLock.unlock()
        invalidatePeersCache()
    }

    /// All pins currently in the Keychain. Takes no lock; must never be
    /// called with `snapshotLock` held.
    private func readPinsFromKeychain() -> [PinSnapshotState.Pin] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.pinService,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain: true,
        ]
        #if !LOCAL_FILE_KEYCHAIN
        query[kSecReturnData] = true
        #endif
        var out: CFTypeRef?
        let status = SecItemCopyMatching(extendPadKeychainQuery(query), &out)
        var fresh: [PinSnapshotState.Pin] = []
        // The data-protection keychain supports attributes + data + match-all
        // in one query. The file-based login keychain returns errSecParam for
        // that combination, so the explicitly labelled local-package build
        // reads the attribute rows first, then each row's data separately.
        if status == errSecSuccess, let items = out as? [[CFString: Any]] {
            fresh = items.compactMap { item in
                guard let peerID = item[kSecAttrAccount] as? String else { return nil }
                #if LOCAL_FILE_KEYCHAIN
                guard let spki = pin(peerID: peerID) else { return nil }
                #else
                guard let spki = item[kSecValueData] as? Data else { return nil }
                #endif
                return PinSnapshotState.Pin(peerID: peerID, spki: spki)
            }
        } else if status != errSecItemNotFound {
            Log.info("ERROR: pin snapshot lookup failed (status \(status))")
        }
        return fresh
    }

    // MARK: - Short ID

    /// Four hex characters that tell same-named Macs apart in lists ("Macbook · 4F2A"). Derived from
    /// the identity key under its own HKDF label, so it shows none of the fingerprint's digits (those
    /// stay hidden until asked for). The same on every device and in the Mac's own Settings.
    static func shortID(spki: Data) -> String {
        let output = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: spki),
                                            salt: WireCrypto.fingerprintHKDFSalt,
                                            info: Data("MeowDisplay short ID v1".utf8), outputByteCount: 2)
        return output.withUnsafeBytes { $0.map { String(format: "%02X", $0) }.joined() }
    }

    /// The paired Mac's short ID, from its pinned key.
    func shortID(peerID: String) -> String? { pin(peerID: peerID).map(Self.shortID(spki:)) }

    // MARK: - Fingerprint

    /// Human-comparable grouped digits: HKDF-SHA256(ikm: spki,
    /// salt: WireCrypto.fingerprintHKDFSalt, info: WireCrypto.fingerprintHKDFInfo,
    /// outputByteCount: 10); split into five 2-byte big-endian integers; each
    /// rendered `% 10000` zero-padded to 4 digits; joined with single spaces.
    /// Example: "0421 9977 1024 0003 8810".
    static func fingerprint(spki: Data) -> String {
        let key = SymmetricKey(data: spki)
        let output = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: WireCrypto.fingerprintHKDFSalt,
            info: WireCrypto.fingerprintHKDFInfo,
            outputByteCount: 10)
        let bytes = output.withUnsafeBytes { Array($0) }
        var groups: [String] = []
        groups.reserveCapacity(5)
        for i in stride(from: 0, to: 10, by: 2) {
            let value = (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
            groups.append(String(format: "%04d", value % 10000))
        }
        return groups.joined(separator: " ")
    }

    // MARK: - Private helpers

    /// The ONLY sanctioned identity retrieval path — never
    /// `SecIdentityCreateWithCertificate`. Must be called with `identityLock`
    /// held.
    private func queryIdentity() -> SecIdentity? {
        #if LOCAL_FILE_KEYCHAIN
        return queryLocalIdentity()
        #else
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: namespace.identityLabel,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(extendPadKeychainQuery(query), &out)
        guard status == errSecSuccess else { return nil }
        // Safe force-cast: errSecSuccess + kSecReturnRef on kSecClassIdentity
        // is documented to yield a SecIdentity; `as!` here is a type-system
        // formality, not a possible-failure force-unwrap.
        return (out as! SecIdentity)
        #endif
    }

    #if LOCAL_FILE_KEYCHAIN
    /// File-keychain identity queries ignore kSecAttrLabel and otherwise return
    /// unrelated identities (including signing identities). Select our labeled
    /// certificate first, then accept only the identity with identical DER.
    private func queryLocalIdentity() -> SecIdentity? {
        var certificateOut: CFTypeRef?
        let certificateStatus = SecItemCopyMatching(extendPadKeychainQuery([
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: namespace.identityLabel,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]), &certificateOut)
        guard certificateStatus == errSecSuccess, let certificateOut else { return nil }
        let expectedDER = SecCertificateCopyData(certificateOut as! SecCertificate) as Data

        var identitiesOut: CFTypeRef?
        let identitiesStatus = SecItemCopyMatching(extendPadKeychainQuery([
            kSecClass: kSecClassIdentity,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]), &identitiesOut)
        guard identitiesStatus == errSecSuccess else { return nil }
        let candidates: [Any]
        if let array = identitiesOut as? [Any] {
            candidates = array
        } else if let identitiesOut {
            candidates = [identitiesOut]
        } else {
            return nil
        }
        for candidate in candidates {
            guard CFGetTypeID(candidate as CFTypeRef) == SecIdentityGetTypeID() else { continue }
            let identity = candidate as! SecIdentity
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
                  let certificate,
                  SecCertificateCopyData(certificate) as Data == expectedDER else { continue }
            return identity
        }
        return nil
    }
    #endif

    /// Must be called with `identityLock` held.
    private func queryInstallID() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.identityLabel,
            kSecAttrAccount: WireCrypto.installIDAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(extendPadKeychainQuery(query), &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Frozen identity-generation call sequence. Must be called with
    /// `identityLock` held. On any failure, deletes whatever partial items
    /// were added and returns nil — no orphans, no crash.
    private func generateAndStoreIdentity() -> SecIdentity? {
        // 1. CryptoKit key — we own the SPKI bytes end to end. The local
        //    package generates its keypair directly inside the login keychain,
        //    then bridges the private key to CryptoKit for self-signing.
        #if LOCAL_FILE_KEYCHAIN
        guard let priv = generateLocalPrivateKey() else { return nil }
        #else
        let priv = P256.Signing.PrivateKey()
        #endif
        let installID = UUID().uuidString

        // 2. Self-sign with swift-certificates (native CryptoKit signer, no
        //    SecKey bridge for signing).
        let certKey: Certificate.PrivateKey
        let certificate: Certificate
        do {
            certKey = Certificate.PrivateKey(priv)
            let name = try DistinguishedName { CommonName(installID) }
            let now = Date()
            certificate = try Certificate(
                version: .v3,
                serialNumber: Certificate.SerialNumber(),
                publicKey: certKey.publicKey,
                notValidBefore: now.addingTimeInterval(-86_400),
                notValidAfter: now.addingTimeInterval(20 * 365 * 86_400),
                issuer: name,
                subject: name,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: try Certificate.Extensions {
                    Critical(BasicConstraints.notCertificateAuthority)
                },
                issuerPrivateKey: certKey)
        } catch {
            Log.info("ERROR: identity self-sign failed: \(error)")
            return nil
        }

        // 3. DER-serialize (SwiftASN1).
        let certDER: Data
        do {
            var serializer = DER.Serializer()
            try serializer.serialize(certificate)
            certDER = Data(serializer.serializedBytes)
        } catch {
            Log.info("ERROR: identity DER serialization failed: \(error)")
            return nil
        }

        #if !LOCAL_FILE_KEYCHAIN
        // 4. Import the private key as a SecKey (X9.63: 04||X||Y||K).
        var cfErr: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(priv.x963Representation as CFData, [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ] as CFDictionary, &cfErr) else {
            Log.info("ERROR: SecKeyCreateWithData failed: \(String(describing: cfErr?.takeRetainedValue()))")
            return nil
        }

        guard let secCert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            Log.info("ERROR: SecCertificateCreateWithData failed")
            return nil
        }
        #endif

        // 5. Persist the identity. The local package's keypair is already in
        //    the login keychain, so only its certificate needs importing.
        var status: OSStatus
        #if LOCAL_FILE_KEYCHAIN
        guard storeLocalCertificate(certDER) else {
            deletePartialIdentityItems()
            return nil
        }
        #else
        // Add key, then cert. The keychain auto-derives the key's
        // kSecAttrApplicationLabel (SHA-1 of public key); the identity forms
        // when that matches the cert's public key — byte-identical here.
        status = SecItemAdd(extendPadKeychainQuery([
            kSecClass: kSecClassKey,
            kSecValueRef: secKey,
            kSecAttrApplicationTag: Data(namespace.identityLabel.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
        ]), nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            Log.info("ERROR: SecItemAdd(key) failed (status \(status))")
            return nil
        }
        status = SecItemAdd(extendPadKeychainQuery([
            kSecClass: kSecClassCertificate,
            kSecValueRef: secCert,
            kSecAttrLabel: namespace.identityLabel,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
        ]), nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            Log.info("ERROR: SecItemAdd(certificate) failed (status \(status))")
            deletePartialIdentityItems()
            return nil
        }
        #endif

        // 6. Persist installID in the SAME namespace (id+key die together).
        status = SecItemAdd(extendPadKeychainQuery([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.identityLabel,
            kSecAttrAccount: WireCrypto.installIDAccount,
            kSecValueData: Data(installID.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
        ]), nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            Log.info("ERROR: SecItemAdd(installID) failed (status \(status))")
            deletePartialIdentityItems()
            return nil
        }

        // 7. Fetch the implicitly-formed identity — the ONLY sanctioned
        //    retrieval (a SecIdentityCreateWithCertificate fallback is
        //    deliberately NOT implemented). The local branch applies the
        //    certificate-DER filter in queryLocalIdentity().
        guard let identity = queryIdentity() else {
            Log.info("ERROR: identity fetch after generation failed")
            deletePartialIdentityItems()
            return nil
        }
        return identity
    }

    #if LOCAL_FILE_KEYCHAIN
    /// Generates the keypair directly inside the encrypted login keychain.
    /// CryptoKit receives an in-memory bridge solely to self-sign the identity;
    /// no private-key file or PKCS#12 export is needed. Normal builds exclude it.
    private func generateLocalPrivateKey() -> P256.Signing.PrivateKey? {
        var keychain: SecKeychain?
        let keychainStatus = SecKeychainCopyDefault(&keychain)
        guard keychainStatus == errSecSuccess, let keychain else {
            Log.info("ERROR: local login keychain unavailable (status \(keychainStatus))")
            return nil
        }
        let tag = Data(namespace.identityLabel.utf8)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecUseKeychain: keychain,
            kSecPublicKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: tag,
                kSecAttrLabel: namespace.identityLabel + ".public",
            ],
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: tag,
                kSecAttrLabel: namespace.identityLabel,
            ],
        ]
        var publicKey: SecKey?
        var privateKey: SecKey?
        let generateStatus = SecKeyGeneratePair(attributes as CFDictionary, &publicKey, &privateKey)
        guard generateStatus == errSecSuccess, let privateKey else {
            Log.info("ERROR: local keypair generation failed (status \(generateStatus))")
            return nil
        }
        var cfErr: Unmanaged<CFError>?
        guard let x963 = SecKeyCopyExternalRepresentation(privateKey, &cfErr) as Data? else {
            Log.info("ERROR: local private-key bridge failed: \(String(describing: cfErr?.takeRetainedValue()))")
            deletePartialIdentityItems()
            return nil
        }
        do {
            return try P256.Signing.PrivateKey(x963Representation: x963)
        } catch {
            Log.info("ERROR: local CryptoKit key reconstruction failed: \(error)")
            deletePartialIdentityItems()
            return nil
        }
    }

    /// Imports the self-signed certificate beside the already-persistent key.
    private func storeLocalCertificate(_ certDER: Data) -> Bool {
        var keychain: SecKeychain?
        let keychainStatus = SecKeychainCopyDefault(&keychain)
        guard keychainStatus == errSecSuccess, let keychain else {
            Log.info("ERROR: local login keychain unavailable (status \(keychainStatus))")
            return false
        }
        var format = SecExternalFormat.formatX509Cert
        var itemType = SecExternalItemType.itemTypeCertificate
        var importedItems: CFArray?
        let importStatus = SecItemImport(
            certDER as CFData,
            nil,
            &format,
            &itemType,
            [],
            nil,
            keychain,
            &importedItems
        )
        guard importStatus == errSecSuccess,
              let items = importedItems as? [Any],
              let rawCertificate = items.first(where: {
                  CFGetTypeID($0 as CFTypeRef) == SecCertificateGetTypeID()
              }) else {
            Log.info("ERROR: local certificate import failed (status \(importStatus))")
            return false
        }
        let certificate = rawCertificate as! SecCertificate
        // SecItemImport uses the certificate CN as its initial label. Apply our
        // namespaced label so lookup, reset and cleanup only touch our items.
        let relabelStatus = SecItemUpdate(
            extendPadKeychainQuery([
                kSecClass: kSecClassCertificate,
                kSecValueRef: certificate,
            ]),
            [kSecAttrLabel: namespace.identityLabel] as CFDictionary
        )
        guard relabelStatus == errSecSuccess else {
            Log.info("ERROR: local certificate namespacing failed (status \(relabelStatus))")
            SecItemDelete(extendPadKeychainQuery([
                kSecClass: kSecClassCertificate,
                kSecValueRef: certificate,
            ]))
            return false
        }
        return true
    }
    #endif

    /// Cleanup for a failed/partial generateAndStoreIdentity() run: deletes
    /// the key (by tag) and cert (by label) so nothing orphaned survives.
    /// Does NOT touch the install-ID row from a prior successful generation.
    private func deletePartialIdentityItems() {
        SecItemDelete(extendPadKeychainQuery([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data(namespace.identityLabel.utf8),
            kSecUseDataProtectionKeychain: true,
        ]))
        SecItemDelete(extendPadKeychainQuery([
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: namespace.identityLabel,
            kSecUseDataProtectionKeychain: true,
        ]))
    }

    /// Same-source SPKI extraction from a certificate already in the
    /// Keychain: cert → SecKey → CryptoKit → DER. The data-protection keychain
    /// returns X9.63, while a file-keychain public key can return DER SPKI.
    /// Never hand-assemble SPKI headers or return raw X9.63 from a public API.
    private func spkiFromCertificate(_ cert: SecCertificate) -> Data? {
        guard let key = SecCertificateCopyKey(cert) else {
            Log.info("ERROR: SecCertificateCopyKey failed")
            return nil
        }
        var cfErr: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(key, &cfErr) as Data? else {
            Log.info("ERROR: SecKeyCopyExternalRepresentation failed: \(String(describing: cfErr?.takeRetainedValue()))")
            return nil
        }
        if let pub = try? P256.Signing.PublicKey(x963Representation: external) {
            return pub.derRepresentation
        }
        #if LOCAL_FILE_KEYCHAIN
        if let pub = try? P256.Signing.PublicKey(derRepresentation: external) {
            return pub.derRepresentation
        }
        #endif
        Log.info("ERROR: P256 public key reconstruction failed")
        return nil
    }
}
