import XCTest
import AppKit

final class MacSenderPipelineStateTests: XCTestCase {

    // MARK: - In-flight encode accounting / admission

    func testAdmitsUntilMaxPendingEncodesThenDrops() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2)
        XCTAssertFalse(state.isBackedUp())
        state.incrementPendingEncodes()
        XCTAssertFalse(state.isBackedUp())
        state.incrementPendingEncodes()
        XCTAssertTrue(state.isBackedUp())
        state.decrementPendingEncodes()
        XCTAssertFalse(state.isBackedUp())
    }

    func testDecrementPendingEncodesNeverGoesNegative() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2)
        state.decrementPendingEncodes()
        state.decrementPendingEncodes()
        state.incrementPendingEncodes()
        XCTAssertFalse(state.isBackedUp())
    }

    func testResetPendingEncodesClearsBackpressure() {
        let state = MacSenderPipelineState(maxPendingEncodes: 1)
        state.incrementPendingEncodes()
        XCTAssertTrue(state.isBackedUp())
        state.resetPendingEncodes()
        XCTAssertFalse(state.isBackedUp())
    }

    func testPendingSendsAtCapacityBacksUpPipeline() {
        let state = MacSenderPipelineState(maxPendingEncodes: 10, maxPendingSends: 1)
        XCTAssertFalse(state.isBackedUp())
        state.incrementPendingSends()
        XCTAssertTrue(state.isBackedUp())
    }

    // MARK: - shouldDropFrame-equivalent admission + drop counters

    func testAdmitFrameDropsAndCountsOnlyWhenAtCapacity() {
        let state = MacSenderPipelineState(maxPendingEncodes: 1)
        XCTAssertFalse(state.admitFrame(reason: "pending_encode"))
        XCTAssertEqual(state.dropsEncTotal, 0)

        state.incrementPendingEncodes()
        XCTAssertTrue(state.admitFrame(reason: "pending_encode"))
        XCTAssertEqual(state.dropsEncTotal, 1)
        XCTAssertEqual(state.dropsEncThisWindow, 1)
        XCTAssertEqual(state.drainPingWindowDrops().enc, 1)
        // Draining resets the ping-window counter but not the this-window one.
        XCTAssertEqual(state.drainPingWindowDrops().enc, 0)
        XCTAssertEqual(state.dropsEncThisWindow, 1)
    }

    func testAdmitFrameNetDropIsIndependentOfEncoderCounters() {
        let state = MacSenderPipelineState(maxPendingEncodes: 10, maxPendingSends: 1)
        state.incrementPendingSends()
        XCTAssertTrue(state.admitFrame(reason: "pending_sends"))
        XCTAssertEqual(state.dropsNetTotal, 1)
        XCTAssertEqual(state.dropsEncTotal, 0)
    }

    func testDrainThisWindowDropsResetsBothCounters() {
        let state = MacSenderPipelineState(maxPendingEncodes: 1, maxPendingSends: 1)
        state.incrementPendingEncodes()
        state.incrementPendingSends()
        _ = state.admitFrame(reason: "pending_encode")
        _ = state.admitFrame(reason: "pending_sends")
        let drained = state.drainThisWindowDrops()
        XCTAssertEqual(drained.enc, 1)
        XCTAssertEqual(drained.net, 1)
        XCTAssertEqual(state.dropsEncThisWindow, 0)
        XCTAssertEqual(state.dropsNetThisWindow, 0)
        // Lifetime totals are untouched by the window drain.
        XCTAssertEqual(state.dropsEncTotal, 1)
        XCTAssertEqual(state.dropsNetTotal, 1)
    }

    // MARK: - Generation / reset semantics

    func testBeginAudioGenerationBumpsMonotonically() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2)
        XCTAssertEqual(state.audioGenerationNow, 0)
        XCTAssertEqual(state.beginAudioGeneration(), 1)
        XCTAssertEqual(state.beginAudioGeneration(), 2)
        XCTAssertEqual(state.audioGenerationNow, 2)
    }

    func testBumpCaptureGenerationIsMonotonic() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2)
        XCTAssertEqual(state.captureGenerationNow, 0)
        state.bumpCaptureGeneration()
        state.bumpCaptureGeneration()
        XCTAssertEqual(state.captureGenerationNow, 2)
    }

    func testWakeCaptureAwaitingGenerationsRoundTripIndependently() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2)
        XCTAssertNil(state.wakeCaptureAwaitingFirstFrameGeneration)
        XCTAssertNil(state.wakeCaptureAwaitingEncodedFrameGeneration)
        state.wakeCaptureAwaitingFirstFrameGeneration = 7
        state.wakeCaptureAwaitingEncodedFrameGeneration = 9
        XCTAssertEqual(state.wakeCaptureAwaitingFirstFrameGeneration, 7)
        XCTAssertEqual(state.wakeCaptureAwaitingEncodedFrameGeneration, 9)
        state.wakeCaptureAwaitingFirstFrameGeneration = nil
        XCTAssertNil(state.wakeCaptureAwaitingFirstFrameGeneration)
        XCTAssertEqual(state.wakeCaptureAwaitingEncodedFrameGeneration, 9)
    }

    // MARK: - Encoder failure streak / recovery bookkeeping

    func testEncodeFailureStreakTriggersRecoveryOnceAtLimit() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2, encodeFailureStreakLimit: 3)
        var recovered = false
        for _ in 0..<2 {
            let (_, shouldAttempt) = state.recordEncodeOutputFailure(-1, at: 0, generation: 1)
            XCTAssertFalse(shouldAttempt)
        }
        let (_, thirdAttempt) = state.recordEncodeOutputFailure(-1, at: 0, generation: 1)
        recovered = thirdAttempt
        XCTAssertTrue(recovered)
        // Same generation must not re-trigger recovery a second time.
        let (_, fourthAttempt) = state.recordEncodeOutputFailure(-1, at: 0, generation: 1)
        XCTAssertFalse(fourthAttempt)
    }

    func testEncodeFailureStreakResetsOnNewGeneration() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2, encodeFailureStreakLimit: 2)
        _ = state.recordEncodeOutputFailure(-1, at: 0, generation: 1)
        let (_, secondGenAttempt) = state.recordEncodeOutputFailure(-1, at: 0, generation: 2)
        // A stale streak from generation 1 must not carry into generation 2.
        XCTAssertFalse(secondGenAttempt)
    }

    func testSuccessfulGenerationSuppressesRecoveryEvenAtStreakLimit() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2, encodeFailureStreakLimit: 1)
        state.recordEncodeSuccess(generation: 1)
        let (_, shouldAttempt) = state.recordEncodeOutputFailure(-1, at: 0, generation: 1)
        XCTAssertFalse(shouldAttempt)
    }

    func testRearmGivesAReplacementEncoderItsOwnStreakAndRecovery() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2, encodeFailureStreakLimit: 2)
        _ = state.recordEncodeOutputFailure(-1, at: 0, generation: 1)
        XCTAssertTrue(state.recordEncodeOutputFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
        state.rearmEncodeFailureRecovery(generation: 1)
        // The streak restarts: one failure is not yet a streak.
        XCTAssertFalse(state.recordEncodeOutputFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
        XCTAssertTrue(state.recordEncodeOutputFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
        XCTAssertFalse(state.recordEncodeOutputFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
    }

    func testRearmForAnotherGenerationLeavesTheCurrentStreakAlone() {
        let state = MacSenderPipelineState(maxPendingEncodes: 2, encodeFailureStreakLimit: 2)
        _ = state.recordEncodeOutputFailure(-1, at: 0, generation: 2)
        state.rearmEncodeFailureRecovery(generation: 1)
        XCTAssertTrue(state.recordEncodeOutputFailure(-1, at: 0, generation: 2).shouldAttemptRecovery)
    }

    // MARK: - Encoder submit-failure bookkeeping

    func testRecordEncodeSubmitFailureDecrementsPendingEncodes() {
        let state = MacSenderPipelineState(maxPendingEncodes: 5)
        state.incrementPendingEncodes()
        state.incrementPendingEncodes()
        _ = state.recordEncodeSubmitFailure(-1, at: 0)
        // One accounted encode remains in flight.
        state.incrementPendingEncodes()
        state.incrementPendingEncodes()
        state.incrementPendingEncodes()
        state.incrementPendingEncodes()
        XCTAssertTrue(state.isBackedUp())
    }

    func testSubmitFailuresCountTowardTheGenerationsStreak() {
        let state = MacSenderPipelineState(maxPendingEncodes: 5, encodeFailureStreakLimit: 3)
        XCTAssertFalse(state.recordEncodeSubmitFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
        XCTAssertFalse(state.recordEncodeOutputFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
        XCTAssertTrue(state.recordEncodeSubmitFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
        XCTAssertFalse(state.recordEncodeSubmitFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
    }

    func testSubmitFailureWithoutAGenerationNeverTriggersRecovery() {
        let state = MacSenderPipelineState(maxPendingEncodes: 5, encodeFailureStreakLimit: 1)
        XCTAssertFalse(state.recordEncodeSubmitFailure(-1, at: 0).shouldAttemptRecovery)
    }

    func testSubmitFailuresAfterASuccessfulFrameNeverTriggerRecovery() {
        let state = MacSenderPipelineState(maxPendingEncodes: 5, encodeFailureStreakLimit: 1)
        state.recordEncodeSuccess(generation: 1)
        XCTAssertFalse(state.recordEncodeSubmitFailure(-1, at: 0, generation: 1).shouldAttemptRecovery)
    }
}

final class CursorImageIdentityTests: XCTestCase {
    private let display = CGSize(width: 2560, height: 1600)

    private func makeCursor(firstByte: UInt8 = 0, hotSpot: NSPoint = .zero) -> NSCursor {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.bitmapData![0] = firstByte
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    func testUnchangedCursorAndDisplayReuseTheirEncodedSprite() {
        let cursor = NSCursor.arrow
        XCTAssertEqual(MacSender.CursorImageStorageIdentity(cursor: cursor, displaySize: display),
                       MacSender.CursorImageStorageIdentity(cursor: cursor, displaySize: display))
        XCTAssertEqual(MacSender.CursorImageIdentity(cursor: cursor, displaySize: display),
                       MacSender.CursorImageIdentity(cursor: cursor, displaySize: display))
    }

    func testSeparateObjectsWithIdenticalPixelsReuseTheirEncodedSprite() {
        let first = makeCursor()
        let second = makeCursor()
        XCTAssertNotEqual(MacSender.CursorImageStorageIdentity(cursor: first, displaySize: display),
                          MacSender.CursorImageStorageIdentity(cursor: second, displaySize: display))
        XCTAssertEqual(MacSender.CursorImageIdentity(cursor: first, displaySize: display),
                       MacSender.CursorImageIdentity(cursor: second, displaySize: display))
    }

    func testPixelHotSpotOrDisplayChangeRequiresANewSprite() {
        let original = MacSender.CursorImageIdentity(cursor: makeCursor(), displaySize: display)
        XCTAssertNotEqual(original, MacSender.CursorImageIdentity(
            cursor: makeCursor(firstByte: 1), displaySize: display))
        XCTAssertNotEqual(original, MacSender.CursorImageIdentity(
            cursor: makeCursor(hotSpot: NSPoint(x: 1, y: 0)), displaySize: display))
        XCTAssertNotEqual(original, MacSender.CursorImageIdentity(
            cursor: makeCursor(), displaySize: CGSize(width: 1920, height: 1080)))
    }

    func testMutableBitmapChangeIsDetectedOnTheSameCursorObject() {
        let cursor = makeCursor()
        let original = MacSender.CursorImageIdentity(cursor: cursor, displaySize: display)
        let bitmap = cursor.image.representations[0] as! NSBitmapImageRep
        bitmap.bitmapData![0] = 1
        XCTAssertNotEqual(original, MacSender.CursorImageIdentity(cursor: cursor, displaySize: display))
    }

    func testUnsupportedRepresentationFallsBackToTIFFContentCheck() {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let cursor = NSCursor(image: image, hotSpot: .zero)
        let identity = MacSender.CursorImageIdentity(cursor: cursor, displaySize: display)
        XCTAssertNil(identity.bitmapHash)
    }
}
