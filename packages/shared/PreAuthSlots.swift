import Foundation

/// Bounds connections that haven't authenticated yet. A listener reachable by anyone on the
/// network (pairing, the Remote Access knock) takes a slot per connection until the peer has
/// proved something; when every slot is taken, newcomers are closed at once. Each slot is
/// also limited in time by `deadline`, so a silent connection can't keep one for long.
///
/// `perSourceLimit` stops one address from taking every slot. The source is only a
/// network address — never an identity — and the bound exists so a single LAN host cannot
/// starve legitimate pairing or knock attempts.
final class PreAuthSlots: @unchecked Sendable {
    /// How long a connection may take to say its first word.
    static let deadline: TimeInterval = 10
    static let pairing = PreAuthSlots(limit: 4)
    static let remoteKnock = PreAuthSlots(limit: 8)

    let limit: Int
    let perSourceLimit: Int
    private let lock = NSLock()
    private var used = 0
    private var bySource: [String: Int] = [:]

    init(limit: Int, perSourceLimit: Int = 2) {
        self.limit = limit
        self.perSourceLimit = perSourceLimit
    }

    /// `source` is a stable description of the peer address (see the callers). A missing
    /// source still counts against the global limit, as before.
    func tryAcquire(source: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard used < limit else { return false }
        if let source, (bySource[source] ?? 0) >= perSourceLimit { return false }
        used += 1
        if let source { bySource[source] = (bySource[source] ?? 0) + 1 }
        return true
    }

    /// Must be called with the same `source` passed to `tryAcquire`.
    func release(source: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        used = max(0, used - 1)
        if let source {
            let left = (bySource[source] ?? 1) - 1
            if left > 0 { bySource[source] = left } else { bySource.removeValue(forKey: source) }
        }
    }

    var inUse: Int {
        lock.lock(); defer { lock.unlock() }
        return used
    }
}

/// Releases a slot exactly once, whichever of handshake, failure or deadline comes first.
final class OneShotRelease: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?

    init(_ action: @escaping () -> Void) { self.action = action }

    var isHeld: Bool {
        lock.lock(); defer { lock.unlock() }
        return action != nil
    }

    func release() {
        lock.lock()
        let run = action
        action = nil
        lock.unlock()
        run?()
    }
}
