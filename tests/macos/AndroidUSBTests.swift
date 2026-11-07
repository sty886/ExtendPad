import XCTest

final class AndroidUSBTests: XCTestCase {
    func testParsesOnlyAuthorizedAdbDevices() {
        let devices = AndroidUSB.parseDevices("""
        List of devices attached
        ELJ6R20C16001081 device usb:1-2 product:MRX-W39 model:MRX_W39 transport_id:2
        OFFLINE offline transport_id:3
        UNAUTHORIZED unauthorized transport_id:4

        """)
        XCTAssertEqual(devices, [AndroidUSBDevice(serial: "ELJ6R20C16001081", model: "MRX_W39")])
        XCTAssertEqual(devices[0].udid, "android:ELJ6R20C16001081")
        XCTAssertEqual(devices[0].displayName, "MRX W39")
    }

    func testSerialValidationRejectsOptionsAndShellSyntax() {
        XCTAssertThrowsError(try AndroidUSB.serial(fromUDID: nil))
        XCTAssertThrowsError(try AndroidUSB.serial(fromUDID: "ios-device"))
        XCTAssertThrowsError(try AndroidUSB.serial(fromUDID: "android:"))
        XCTAssertThrowsError(try AndroidUSB.serial(fromUDID: "android:-s"))
        XCTAssertThrowsError(try AndroidUSB.serial(fromUDID: "android:serial;rm"))
        XCTAssertEqual(try AndroidUSB.serial(fromUDID: "android:emulator-5554"), "emulator-5554")
    }

    func testSyntheticUSBDeviceKeepsTheStableAndroidPrefix() {
        let device = AndroidUSBDevice(serial: "SERIAL-1", model: nil)
        let listed = AndroidUSB.asUSBDevice(device)
        XCTAssertEqual(listed.udid, "android:SERIAL-1")
        XCTAssertEqual(listed.name, "Android tablet")
        XCTAssertTrue(AndroidUSB.isAndroidUDID(listed.udid))
        XCTAssertFalse(AndroidUSB.isAndroidUDID("00008140-000450C82698801C"))
    }

    func testTunnelUsesHostToDeviceForwardWithoutOccupyingReceiverPort() {
        XCTAssertEqual(
            AndroidUSB.tunnelArguments(serial: "SERIAL-1", port: 9001),
            ["-s", "SERIAL-1", "forward", "tcp:9001", "tcp:9001"])
    }

    func testDiscoveryUsesDeviceToHostReverseWithoutStartingMedia() {
        XCTAssertEqual(
            AndroidUSB.discoveryReverseArguments(serial: "SERIAL-1"),
            ["-s", "SERIAL-1", "reverse", "tcp:9005", "tcp:9005"])
    }

    func testDiscoveryWireUsesVersionedLengthPrefixedJSON() throws {
        let request = USBHostRequest(version: 1, action: .connect, peerID: "MAC-ID")
        let frame = try USBHostDiscoveryWire.frame(request)
        let length = Int(frame.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        XCTAssertEqual(length, frame.count - 4)
        XCTAssertEqual(try USBHostDiscoveryWire.request(from: frame.dropFirst(4)), request)

        let advertisement = USBHostAdvertisement(version: 1, peerID: "MAC-ID", name: "Mac", paired: true, platform: "macos")
        let encoded = try USBHostDiscoveryWire.frame(advertisement)
        XCTAssertEqual(try USBHostDiscoveryWire.advertisement(from: encoded.dropFirst(4)), advertisement)
    }

    func testDiscoveryRequestCarriesTheReceiversInstallID() throws {
        let request = USBHostRequest(version: 1, action: .connect, peerID: "MAC-ID", receiverID: "RECEIVER-ID")
        let frame = try USBHostDiscoveryWire.frame(request)
        XCTAssertEqual(try USBHostDiscoveryWire.request(from: frame.dropFirst(4)), request)

        // Older receivers omit it, so decoding must treat it as nil.
        let legacy = try USBHostDiscoveryWire.request(from: Data(
            #"{"version":1,"action":"connect","peerID":"MAC-ID"}"#.utf8))
        XCTAssertNil(legacy.receiverID)
    }

    func testDiscoveryWireRejectsAnIncompatibleVersion() {
        XCTAssertThrowsError(try USBHostDiscoveryWire.request(from: Data(
            #"{"version":2,"action":"discover"}"#.utf8)))
    }

    func testTunnelPreparationOnlyRepeatsForANewOrLostDevice() {
        XCTAssertTrue(AndroidUSB.tunnelNeedsRefresh(serial: "SERIAL-1", preparedSerial: nil))
        XCTAssertFalse(AndroidUSB.tunnelNeedsRefresh(serial: "SERIAL-1", preparedSerial: "SERIAL-1"))
        XCTAssertTrue(AndroidUSB.tunnelNeedsRefresh(serial: "SERIAL-2", preparedSerial: "SERIAL-1"))
    }
}
