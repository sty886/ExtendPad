import XCTest

/// A receiver's Connect names the one sender its user tapped (TXT `crt`).
/// Every other paired sender must stay quiet so it can't briefly take over
/// the session that was actually asked for (PROTOCOL.md 6.9).
final class ReceiverConnectRequestTargetingTests: XCTestCase {
    func testOnlyTheNamedSenderAnswersATargetedRequest() {
        XCTAssertTrue(ReceiverConnectRequestTargeting.addressed(to: "sender-a", target: "sender-a"))
        XCTAssertFalse(ReceiverConnectRequestTargeting.addressed(to: "sender-b", target: "sender-a"))
    }

    func testARequestThatNamesNobodyStillReachesEveryPairedSender() {
        // Receivers before `crt` publish no target; they must keep working.
        XCTAssertTrue(ReceiverConnectRequestTargeting.addressed(to: "sender-a", target: nil))
        XCTAssertTrue(ReceiverConnectRequestTargeting.addressed(to: "sender-a", target: ""))
    }

    func testAnEmptyOwnIdentityNeverMatchesATarget() {
        XCTAssertFalse(ReceiverConnectRequestTargeting.addressed(to: nil, target: "sender-a"))
        XCTAssertFalse(ReceiverConnectRequestTargeting.addressed(to: "", target: "sender-a"))
    }
}
