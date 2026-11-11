import Foundation
import XCTest

/// A peer that never stops sending frames. Used to prove the pairing pump
/// cannot be made to buffer unbounded data while the SAS prompt is on screen.
private final class FloodTransport: PairingTransport, @unchecked Sendable {
    let kind: PairingEnvelope.Kind

    init(kind: PairingEnvelope.Kind) { self.kind = kind }

    func send(_ envelope: PairingEnvelope) async throws {}
    func receive() async throws -> PairingEnvelope {
        .step(kind, Data(repeating: 0x42, count: 32))
    }
    func sendLastAndClose(_ envelope: PairingEnvelope?) {}
}

final class PairingPumpBoundTests: XCTestCase {
    private func pairingResult() throws -> PairingResult {
        let phone = PairingHandshake(
            role: .initiator, deviceID: "22222222-2222-2222-2222-222222222222",
            displayName: "Phone", identitySPKI: TestSPKI.of("phone identity"))
        let mac = PairingHandshake(
            role: .responder, deviceID: "11111111-1111-1111-1111-111111111111",
            displayName: "Mac", identitySPKI: TestSPKI.of("mac identity"))
        return try mac.result(peerHello: phone.localHello)
    }

    /// After `helloReveal`, a `hello`/`helloCommit`/`helloReveal` frame can
    /// never be legitimate. It is rejected on sight, before it is buffered.
    func testPumpRejectsFramesThatCannotFollowTheHelloCeremony() async throws {
        let pump = PairingFramePump(
            transport: FloodTransport(kind: .hello),
            result: try pairingResult(), onPeerAbort: {})
        do {
            _ = try await pump.next()
            XCTFail("a post-hello hello frame must end the attempt")
        } catch let error as PairingError {
            XCTAssertEqual(error, .malformedMessage)
        }
    }

    /// While the local decision is pending, a peer may legitimately send at
    /// most one confirmation. A stream of well-formed frames must hit the
    /// bound and fail the attempt instead of growing memory with the SAS
    /// prompt still on screen.
    func testPumpBoundsAFrameFloodWhileTheSASPromptIsUp() async throws {
        let pump = PairingFramePump(
            transport: FloodTransport(kind: .commit),
            result: try pairingResult(), onPeerAbort: {})
        // Give the producer time to fill the bounded buffer before consuming.
        try? await Task.sleep(nanoseconds: 150_000_000)

        var sawFlood = false
        for _ in 0..<(PairingFramePump.maxBufferedFrames + 8) {
            do {
                _ = try await pump.next()
            } catch let error as PairingError {
                sawFlood = error == .tooManyAttempts
                break
            } catch {
                break
            }
        }
        XCTAssertTrue(sawFlood, "a pairing frame flood must fail the attempt, not grow without bound")
    }
}
