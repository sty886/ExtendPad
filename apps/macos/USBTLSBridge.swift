// USB is a route, not a trust mode. USBTLSBridge turns Android's ADB tunnel
// into a plain loopback TCP endpoint that MacSender can dial with the EXACT
// SAME TLSConfigurator/TLSSessionConfig path used for LAN and Remote. It has
// zero cryptography and zero protocol awareness: it relays opaque bytes in
// both directions between the tunnel and one local TCP connection. TLS 1.3
// mutual authentication and SPKI/TrustStore pin verification happen outside
// this file, on the connection that dials the port this bridge exposes.
//
// Network.framework cannot layer NWProtocolTLS onto an NWConnection after it
// is connected. The ADB tunnel is already connected and carries no TLS of its
// own, so this loopback splice reuses Network.framework's TLS engine without
// creating a second trust boundary.

import Foundation
import Network

/// Bidirectional, bounded, opaque byte relay between two already-started
/// `NWConnection`s. Never inspects content. Tears both legs down the moment
/// either side EOFs, fails to send, fails to receive, or is cancelled.
// `a`, `b`, and `onTornDown` are immutable and Sendable; the only mutable
// field, `torn`, is only ever read/written under `lock`.
private final class ByteSplice: @unchecked Sendable {
    private let a: NWConnection
    private let b: NWConnection
    private let onTornDown: @Sendable () -> Void
    private let lock = NSLock()
    private var torn = false

    init(_ a: NWConnection, _ b: NWConnection, onTornDown: @escaping @Sendable () -> Void) {
        self.a = a
        self.b = b
        self.onTornDown = onTornDown
    }

    func start() {
        pump(from: a, to: b)
        pump(from: b, to: a)
    }

    private func pump(from src: NWConnection, to dst: NWConnection) {
        // 64 KiB: generous enough for a video frame chunk without letting
        // an unbounded amount of ciphertext queue up in this process.
        src.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                dst.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil || isComplete || error != nil {
                        self.teardown()
                    } else {
                        self.pump(from: src, to: dst)
                    }
                })
            } else if isComplete || error != nil {
                teardown()
            } else {
                pump(from: src, to: dst)
            }
        }
    }

    func teardown() {
        lock.lock()
        let alreadyTorn = torn
        torn = true
        lock.unlock()
        guard !alreadyTorn else { return }
        a.cancel()
        b.cancel()
        onTornDown()
    }
}

/// Establishes one Android ADB tunnel to the receiver's trusted TLS media
/// port and exposes it as a one-shot local loopback listener.
///
/// Lifecycle: `start()` opens the tunnel and binds the local listener, then
/// returns the local port. The listener accepts exactly one connection —
/// cancelling itself synchronously, before any other work, inside that same
/// accept callback — and from then on relays opaque bytes between that one
/// local connection and the tunnel. `cancel()` tears everything down
/// (idempotent, safe to call at any point in the lifecycle, from any queue).
///
/// A local process that connects to the bridge port before the intended
/// client does would only ever see itself accepted as that one connection
/// (denial-of-service at worst) — it gains no MEOW session, because nothing
/// here performs or implies authentication. That happens entirely on the
/// far side of the splice, in `TLSConfigurator`, unaffected by this file.
///
/// All mutable state (`tunnel`, `listener`, `splice`, `cancelled`) is
/// actor-isolated rather than merely convention-confined to `queue`: the
/// compiler, not a comment, now enforces the single-owner invariant this
/// type has always relied on.
actor USBTLSBridge {
    enum Failure: Error, LocalizedError {
        case listenerFailed(Error)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .listenerFailed(let error): return "USB secure bridge listener failed: \(error)"
            case .cancelled: return "USB secure bridge was cancelled"
            }
        }
    }

    private let udid: String?
    // Not this actor's synchronization mechanism (the actor already
    // serializes `tunnel`/`listener`/`splice`/`cancelled`) — this is the
    // Network.framework callback queue every NWListener/NWConnection here
    // is started on, kept as a caller-supplied queue because `dialTunnel`
    // (`AndroidUSB.dial` in production) requires one.
    private let queue: DispatchQueue
    private let dialTunnel: (String?, UInt16, DispatchQueue) async throws -> NWConnection
    private var tunnel: NWConnection?
    private var listener: NWListener?
    private var splice: ByteSplice?
    private var cancelled = false
    private var resumedStart = false

    /// `dialTunnel` is `AndroidUSB.dial` in production (always targeting
    /// `WireCrypto.tlsPort` — see `start()`) and an injected fake opaque
    /// tunnel in tests. Every call site stays explicit about what it dials.
    init(udid: String?, queue: DispatchQueue,
         dialTunnel: @escaping (String?, UInt16, DispatchQueue) async throws -> NWConnection) {
        self.udid = udid
        self.queue = queue
        self.dialTunnel = dialTunnel
    }

    /// Dials the ADB tunnel (`WireCrypto.tlsPort` — the receiver's trusted
    /// TLS media listener, never the legacy plaintext port) and binds the
    /// local one-shot listener. Throws without leaving anything running on
    /// failure.
    func start() async throws -> NWEndpoint.Port {
        let tunnelConn = try await dialTunnel(udid, WireCrypto.tlsPort, queue)
        guard !cancelled else {
            tunnelConn.cancel()
            throw Failure.cancelled
        }
        tunnel = tunnelConn
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 0)
        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            tunnel = nil
            tunnelConn.cancel()
            throw Failure.listenerFailed(error)
        }
        self.listener = listener
        return try await withCheckedThrowingContinuation { cont in
            // `listener.cancel()` is idempotent and thread-safe on its own,
            // so it's called unconditionally and synchronously right here,
            // on the raw Network.framework callback, rather than after
            // hopping onto the actor — that keeps the one-accept race
            // window as tight as the original queue-confined
            // implementation's. Which accepted connection (if more than
            // one raced in) actually wins is still decided by actor state,
            // in `acceptFirstConnection`.
            listener.newConnectionHandler = { [weak self] localConn in
                guard let self else { localConn.cancel(); return }
                listener.cancel()
                Task { await self.acceptFirstConnection(localConn, listener: listener, tunnelConn: tunnelConn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { await self.handleListenerState(state, listener: listener, continuation: cont) }
            }
            listener.start(queue: queue)
        }
    }

    private var acceptedConnection = false

    /// One-shot: only ever act on the FIRST accepted connection — later
    /// racing accepts (the listener may already be cancelled but a second
    /// connection can still land in `newConnectionHandler`) are rejected
    /// here by actor-isolated state, never spliced to anything.
    private func acceptFirstConnection(_ localConn: NWConnection, listener: NWListener, tunnelConn: NWConnection) {
        guard !cancelled, !acceptedConnection else {
            localConn.cancel()
            return
        }
        acceptedConnection = true
        self.listener = nil
        localConn.start(queue: queue)
        let splice = ByteSplice(localConn, tunnelConn) { [weak self] in
            self?.cancel()
        }
        self.splice = splice
        splice.start()
    }

    private func handleListenerState(
        _ state: NWListener.State, listener: NWListener,
        continuation: CheckedContinuation<NWEndpoint.Port, Error>
    ) {
        guard self.listener === listener else { return }
        switch state {
        case .ready:
            guard !resumedStart, let port = listener.port else { return }
            resumedStart = true
            continuation.resume(returning: port)
        case .failed(let error):
            if !resumedStart {
                resumedStart = true
                continuation.resume(throwing: Failure.listenerFailed(error))
            }
            performCancel()
        default:
            break
        }
    }

    /// Tears down whatever part of the bridge is currently alive. Idempotent
    /// and safe to call from any queue, at any point in the lifecycle —
    /// before `start()` returns, mid-splice, or after normal teardown.
    nonisolated func cancel() {
        Task { await self.performCancel() }
    }

    private func performCancel() {
        guard !cancelled else { return }
        cancelled = true
        listener?.cancel()
        listener = nil
        splice?.teardown()
        splice = nil
        tunnel?.cancel()
        tunnel = nil
    }
}
