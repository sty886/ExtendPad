import Network
import XCTest

/// The USB discovery socket exists only for `adb reverse`, which connects to
/// the host's loopback. It must never be reachable from the LAN.
final class USBHostDiscoveryTests: XCTestCase {
    func testDiscoveryListenerBindsLoopbackOnly() {
        let params = USBHostDiscoveryListener.listenerParameters()
        guard case .hostPort(let host, let port)? = params.requiredLocalEndpoint else {
            return XCTFail("USB discovery must have a fixed local endpoint")
        }
        XCTAssertEqual(String(describing: host), "127.0.0.1")
        XCTAssertEqual(port.rawValue, USBHostDiscoveryWire.port)
    }
}
