import Foundation
import Network

enum USBHostAction: String, Codable, Equatable, Sendable {
    case discover
    case connect
    case pair
}

struct USBHostRequest: Codable, Equatable, Sendable {
    let version: Int
    let action: USBHostAction
    /// The Mac this request is addressed to.
    let peerID: String?
    /// The receiver's own install id: an unauthenticated hint that lets the Mac
    /// match this USB device to a peer it has already pinned (for example one
    /// paired over Wi-Fi). It never grants trust — the pinned TLS handshake
    /// still decides.
    let receiverID: String?

    init(version: Int, action: USBHostAction, peerID: String?, receiverID: String? = nil) {
        self.version = version
        self.action = action
        self.peerID = peerID
        self.receiverID = receiverID
    }
}

struct USBHostAdvertisement: Codable, Equatable, Sendable {
    let version: Int
    let peerID: String
    let name: String
    let paired: Bool
    let platform: String
}

enum USBHostDiscoveryWire {
    static let version = 1
    static let port: UInt16 = 9005
    static let maximumMessageBytes = 16 * 1024

    static func frame<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maximumMessageBytes else { throw USBHostDiscoveryError.invalidMessage }
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }

    static func request(from body: Data) throws -> USBHostRequest {
        let request = try JSONDecoder().decode(USBHostRequest.self, from: body)
        guard request.version == version else { throw USBHostDiscoveryError.invalidMessage }
        return request
    }

    static func advertisement(from body: Data) throws -> USBHostAdvertisement {
        let advertisement = try JSONDecoder().decode(USBHostAdvertisement.self, from: body)
        guard advertisement.version == version else { throw USBHostDiscoveryError.invalidMessage }
        return advertisement
    }
}

enum USBHostDiscoveryError: Error {
    case invalidMessage
}

/// Publishes USB availability without starting pairing or media. A request is
/// only a hint: the controller still checks pairing and every media session
/// uses the existing pinned mutual-TLS transport.
@MainActor
final class USBHostDiscoveryListener {
    private let advertisement: () -> USBHostAdvertisement?
    private let onRequest: (USBHostRequest) -> Void
    private var listener: NWListener?

    init(
        advertisement: @escaping () -> USBHostAdvertisement?,
        onRequest: @escaping (USBHostRequest) -> Void
    ) {
        self.advertisement = advertisement
        self.onRequest = onRequest
    }

    /// The only client is `adb reverse`, which dials the host's
    /// 127.0.0.1:9005. Binding to every interface exposed an unauthenticated
    /// discovery/connect/pair surface to the whole LAN for no benefit.
    nonisolated static func listenerParameters() -> NWParameters {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: USBHostDiscoveryWire.port)!)
        return params
    }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: Self.listenerParameters())
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    connection.start(queue: .main)
                    self?.receiveRequest(connection, accumulated: Data())
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Log.info("usbDiscovery: listener failed: \(error)")
                }
            }
            listener.start(queue: .main)
        } catch {
            Log.info("usbDiscovery: listener unavailable: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receiveRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: USBHostDiscoveryWire.maximumMessageBytes + 4) {
            [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.listener != nil else { connection.cancel(); return }
                var accumulated = accumulated
                if let data { accumulated.append(data) }
                guard error == nil, !(complete && accumulated.isEmpty) else { connection.cancel(); return }
                guard accumulated.count >= 4 else {
                    self.receiveRequest(connection, accumulated: accumulated)
                    return
                }
                let length = Int(accumulated.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                guard length > 0, length <= USBHostDiscoveryWire.maximumMessageBytes else {
                    connection.cancel()
                    return
                }
                guard accumulated.count >= length + 4 else {
                    self.receiveRequest(connection, accumulated: accumulated)
                    return
                }
                let body = accumulated.subdata(in: 4..<(length + 4))
                guard let request = try? USBHostDiscoveryWire.request(from: body) else {
                    Log.info("usbDiscovery: invalid request")
                    connection.cancel()
                    return
                }
                guard let advertisement = self.advertisement() else {
                    Log.info("usbDiscovery: host identity unavailable")
                    connection.cancel()
                    return
                }
                guard let response = try? USBHostDiscoveryWire.frame(advertisement) else {
                    connection.cancel()
                    return
                }
                connection.send(content: response, completion: .contentProcessed { _ in
                    Task { @MainActor in
                        connection.cancel()
                        if request.action != .discover { self.onRequest(request) }
                    }
                })
            }
        }
    }
}
