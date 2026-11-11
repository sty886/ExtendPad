package com.raisecaterror.meowdisplay.core

import com.raisecaterror.meowdisplay.core.Fixtures.obj
import com.raisecaterror.meowdisplay.core.pairing.PairingEnvelope
import com.raisecaterror.meowdisplay.core.pairing.PairingError
import com.raisecaterror.meowdisplay.core.pairing.PairingException
import com.raisecaterror.meowdisplay.core.pairing.PairingFramePump
import com.raisecaterror.meowdisplay.core.pairing.PairingRole
import com.raisecaterror.meowdisplay.core.pairing.PairingTransport
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The pairing pump must never let an unauthenticated peer grow memory while the SAS is shown. */
class PairingPumpBoundTest {
    private class FloodTransport(private val kind: PairingEnvelope.Kind) : PairingTransport {
        override suspend fun send(envelope: PairingEnvelope) {}
        override suspend fun receive(): PairingEnvelope = PairingEnvelope.step(kind, ByteArray(32))
        override fun sendLastAndClose(envelope: PairingEnvelope?) {}
    }

    private fun result() = Fixtures.pairingCases.first().let { case ->
        Fixtures.handshake(case.obj("responder"), PairingRole.Responder)
            .result(Fixtures.handshake(case.obj("initiator"), PairingRole.Initiator).localHello)
    }

    @Test
    fun pumpRejectsFramesThatCannotFollowTheHelloCeremony() = runBlocking {
        val pump = PairingFramePump(
            FloodTransport(PairingEnvelope.Kind.Hello), result(), onPeerAbort = {})
        val error = runCatching { pump.next() }.exceptionOrNull() as? PairingException
        assertEquals(PairingError.MalformedMessage, error?.error)
        pump.stop()
    }

    @Test
    fun pumpBoundsAFloodWhileTheDecisionIsPending() = runBlocking {
        val pump = PairingFramePump(
            FloodTransport(PairingEnvelope.Kind.Commit), result(), onPeerAbort = {})
        // Let the producer fill the bounded channel before consuming, exactly
        // as it would while the local SAS prompt waits for the user.
        delay(500)
        var sawFlood = false
        for (i in 0 until PairingFramePump.MAX_BUFFERED_FRAMES + 8) {
            val error = runCatching { pump.next() }.exceptionOrNull() as? PairingException ?: continue
            sawFlood = error.error == PairingError.TooManyAttempts
            break
        }
        pump.stop()
        assertTrue("a pairing frame flood must fail the attempt, not grow without bound", sawFlood)
    }
}
