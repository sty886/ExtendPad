import Foundation
import XCTest

/// `hello.pixelsWide/High/scale` are untrusted wire values. A paired receiver
/// must not be able to send geometry that overflows the sender's
/// point/pixel → `Int`/`UInt32` conversions.
final class PhoneInfoGeometryTests: XCTestCase {
    private func info(_ json: String) throws -> PhoneInfo {
        try JSONDecoder().decode(PhoneInfo.self, from: Data(json.utf8))
    }

    func testARealPanelIsAccepted() throws {
        let value = try info(#"{"pixelsWide":2556,"pixelsHigh":1179,"scale":3}"#)
        XCTAssertTrue(value.hasSaneGeometry)
        let macReceiver = try info(#"{"pixelsWide":3024,"pixelsHigh":1964,"scale":2}"#)
        XCTAssertTrue(macReceiver.hasSaneGeometry)
    }

    func testAbsurdOrZeroGeometryIsRejectedBeforeAnyDisplayMath() throws {
        // 9e18 is representable as Int and used to reach UInt32(...) unchecked.
        XCTAssertFalse(try info(#"{"pixelsWide":9000000000000000000,"pixelsHigh":1179,"scale":3}"#).hasSaneGeometry)
        XCTAssertFalse(try info(#"{"pixelsWide":0,"pixelsHigh":1179,"scale":3}"#).hasSaneGeometry)
        XCTAssertFalse(try info(#"{"pixelsWide":-2556,"pixelsHigh":1179,"scale":3}"#).hasSaneGeometry)
        XCTAssertFalse(try info(#"{"pixelsWide":2556,"pixelsHigh":20000,"scale":3}"#).hasSaneGeometry)
    }

    func testImplausibleScaleIsRejected() throws {
        XCTAssertFalse(try info(#"{"pixelsWide":2556,"pixelsHigh":1179,"scale":0}"#).hasSaneGeometry)
        XCTAssertFalse(try info(#"{"pixelsWide":2556,"pixelsHigh":1179,"scale":-1}"#).hasSaneGeometry)
        XCTAssertFalse(try info(#"{"pixelsWide":2556,"pixelsHigh":1179,"scale":100}"#).hasSaneGeometry)
    }
}
