// Android USB uses ADB only as an opaque byte tunnel. Pairing, mutual TLS 1.3
// and SPKI pinning remain the same as on LAN. ADB is never used to inject
// input, read app data, or trust a device automatically.

import Foundation
import Network

struct USBDevice: Hashable, Identifiable, Sendable {
    let deviceID: Int
    let udid: String
    var name: String?

    var id: String { udid }
    var label: String { "\(name ?? "Android") (USB)" }
}

struct AndroidUSBDevice: Equatable, Sendable {
    let serial: String
    let model: String?

    var udid: String { AndroidUSB.udidPrefix + serial }
    var displayName: String { model?.replacingOccurrences(of: "_", with: " ") ?? "Android tablet" }
}

enum AndroidUSB {
    static let udidPrefix = "android:"

    enum Failure: Error, LocalizedError {
        case adbUnavailable
        case invalidDevice
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .adbUnavailable:
                return "Android SDK platform-tools (adb) is not installed"
            case .invalidDevice:
                return "Invalid Android USB device identifier"
            case .commandFailed(let detail):
                return "Android USB tunnel failed: \(detail)"
            }
        }
    }

    static func isAndroidUDID(_ udid: String?) -> Bool {
        udid?.hasPrefix(udidPrefix) == true
    }

    static func serial(fromUDID udid: String?) throws -> String {
        guard let udid, udid.hasPrefix(udidPrefix) else { throw Failure.invalidDevice }
        let serial = String(udid.dropFirst(udidPrefix.count))
        // Never allow an identifier to become an adb option or shell syntax.
        guard !serial.isEmpty, !serial.hasPrefix("-"),
              serial.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" || $0 == ":" }) else {
            throw Failure.invalidDevice
        }
        return serial
    }

    static func parseDevices(_ output: String) -> [AndroidUSBDevice] {
        output.components(separatedBy: .newlines).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[1] == "device", fields[0] != "List" else { return nil }
            let model = fields.dropFirst(2).first(where: { $0.hasPrefix("model:") }).map {
                String($0.dropFirst("model:".count))
            }
            return AndroidUSBDevice(serial: fields[0], model: model)
        }
    }

    static func adbURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let explicit = environment["EXTENDPAD_ADB"] { candidates.append(explicit) }
        for root in [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]] {
            if let root { candidates.append(root + "/platform-tools/adb") }
        }
        candidates.append(NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb")
        candidates.append("/opt/homebrew/bin/adb")
        candidates.append("/usr/local/bin/adb")
        return candidates.map(URL.init(fileURLWithPath:)).first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        guard let adb = adbURL() else { throw Failure.adbUnavailable }
        let process = Process()
        let output = Pipe()
        process.executableURL = adb
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw Failure.commandFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw Failure.commandFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }

    static func tunnelArguments(serial: String, port: UInt16) -> [String] {
        ["-s", serial, "forward", "tcp:\(port)", "tcp:\(port)"]
    }

    static func discoveryReverseArguments(serial: String) -> [String] {
        ["-s", serial, "reverse", "tcp:\(USBHostDiscoveryWire.port)", "tcp:\(USBHostDiscoveryWire.port)"]
    }

    private static func prepare(serial: String, port: UInt16) throws {
        try run(tunnelArguments(serial: serial, port: port))
    }

    /// ADB forwarding survives app and tunnel reconnects while the same authorized device stays
    /// attached. Reuse it instead of launching three redundant ADB processes on every discovery tick.
    static func tunnelNeedsRefresh(serial: String, preparedSerial: String?) -> Bool {
        serial != preparedSerial
    }

    private static func connectedDevicesSync(preparedSerial: String?) -> (devices: [AndroidUSBDevice], preparedSerial: String?) {
        guard adbURL() != nil, let output = try? run(["devices", "-l"]) else { return ([], nil) }
        // Host port 9001/9002 can forward to only one Android device. Refuse
        // to guess among several tablets rather than risk pairing the wrong one.
        let devices = parseDevices(output)
        guard devices.count == 1, let device = devices.first else { return ([], nil) }
        guard tunnelNeedsRefresh(serial: device.serial, preparedSerial: preparedSerial) else {
            return ([device], device.serial)
        }
        do {
            try prepare(serial: device.serial, port: WireCrypto.tlsPort)
            try prepare(serial: device.serial, port: WireCrypto.pairingPort)
            try run(discoveryReverseArguments(serial: device.serial))
            return ([device], device.serial)
        } catch {
            Log.info("androidUSB: setup failed: \(error.localizedDescription)")
            return ([], nil)
        }
    }

    static func connectedDevices(preparedSerial: String? = nil) async -> (devices: [AndroidUSBDevice], preparedSerial: String?) {
        await Task.detached(priority: .utility) { connectedDevicesSync(preparedSerial: preparedSerial) }.value
    }

    /// Dial the ADB-forwarded port as a raw connection. USBTLSBridge then
    /// carries only the receiver's normal TLS ciphertext across this tunnel.
    static func dial(udid: String?, port: UInt16, queue: DispatchQueue) async throws -> NWConnection {
        let serial = try serial(fromUDID: udid)
        try await Task.detached(priority: .userInitiated) { try prepare(serial: serial, port: port) }.value
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw Failure.invalidDevice }
        let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: endpointPort), using: .tcp)
        connection.start(queue: queue)
        return connection
    }

    static func asUSBDevice(_ device: AndroidUSBDevice) -> USBDevice {
        // Stable FNV-1a: only a synthetic list key, never a security identity.
        var hash: UInt32 = 2_166_136_261
        for byte in device.serial.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return USBDevice(deviceID: Int(hash), udid: device.udid, name: device.displayName)
    }
}

@MainActor
final class AndroidUSBDeviceWatcher {
    private let onChange: ([USBDevice]) -> Void
    private var task: Task<Void, Never>?

    init(onChange: @escaping ([USBDevice]) -> Void) {
        self.onChange = onChange
        task = Task { [weak self] in
            var preparedSerial: String?
            var ticks = 0
            while !Task.isCancelled {
                // adb forwards/reverses die with the adb server, while this watcher's
                // preparedSerial survives. Re-assert them periodically (and after a
                // server restart) instead of waiting for the device serial to change.
                if ticks % 20 == 0 { preparedSerial = nil }
                ticks += 1
                let result = await AndroidUSB.connectedDevices(preparedSerial: preparedSerial)
                preparedSerial = result.preparedSerial
                self?.onChange(result.devices.map(AndroidUSB.asUSBDevice))
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    isolated deinit {
        task?.cancel()
    }
}
