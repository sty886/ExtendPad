package com.raisecaterror.meowdisplay.core.usb

import com.raisecaterror.meowdisplay.core.remote.HostPlatform
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.nio.ByteBuffer

class USBHostDiscoveryWireTest {
    @Test
    fun adbDiscoveryKeepsTheVersionOneWireShape() {
        val request = USBHostRequest(1, USBHostAction.Connect, "MAC-ID")
        val framed = USBHostDiscoveryWire.frame(request)
        assertEquals(framed.size - 4, ByteBuffer.wrap(framed).int)
        assertEquals(request, USBHostDiscoveryWire.request(framed.copyOfRange(4, framed.size)))

        val body = """{"version":1,"peerID":"MAC-ID","name":"Mac","paired":true}""".toByteArray()
        assertEquals(USBHostAdvertisement(1, "MAC-ID", "Mac", true), USBHostDiscoveryWire.advertisement(body))
        val linux = """{"version":1,"peerID":"SERVER-ID","name":"Ubuntu","paired":false,"platform":"linux"}""".toByteArray()
        assertEquals(HostPlatform.LINUX, USBHostDiscoveryWire.advertisement(linux).platform)
    }

    @Test
    fun adbConnectAndPairCarryTheReceiversInstallID() {
        val request = USBHostRequest(1, USBHostAction.Connect, "MAC-ID", "RECEIVER-ID")
        val framed = USBHostDiscoveryWire.frame(request)
        assertEquals(request, USBHostDiscoveryWire.request(framed.copyOfRange(4, framed.size)))

        val legacy = USBHostDiscoveryWire.request(
            """{"version":1,"action":"connect","peerID":"MAC-ID"}""".toByteArray()
        )
        assertEquals(null, legacy.receiverID)
    }

    @Test
    fun aoaMessagesUseVersionTwoAndAType() {
        val request = USBHostRequest(2, USBHostAction.Connect, "MAC-ID", "RECEIVER-ID")
        val framed = USBAccessoryWire.frame(request)
        assertEquals(framed.size - 4, ByteBuffer.wrap(framed).int)
        assertEquals(request, USBAccessoryWire.request(framed.copyOfRange(4, framed.size)))

        val ad = USBAccessoryWire.parse(
            """{"type":"advertisement","version":2,"peerID":"MAC-ID","name":"Mac","paired":true}""".toByteArray()
        )
        assertEquals(USBHostAdvertisement(2, "MAC-ID", "Mac", true), (ad as USBAccessoryMessage.Advertisement).advertisement)
    }

    @Test
    fun aoaRelayCarriesTheLocalListenerPort() {
        val framed = USBAccessoryWire.relayFrame(USBAccessoryWire.TLS_RELAY_PORT)
        assertEquals(framed.size - 4, ByteBuffer.wrap(framed).int)
        val parsed = USBAccessoryWire.parse(framed.copyOfRange(4, framed.size))
        assertEquals(USBAccessoryMessage.Relay(USBAccessoryRelay(2, 9001)), parsed)

        val pairing = USBAccessoryWire.parse("""{"type":"relay","version":2,"port":9002}""".toByteArray())
        assertEquals(9002, (pairing as USBAccessoryMessage.Relay).relay.port)
        assertThrows(IllegalArgumentException::class.java) {
            USBAccessoryWire.parse("""{"type":"relay","version":2,"port":0}""".toByteArray())
        }
    }

    @Test
    fun incompatibleOrOversizedMessagesAreRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            USBHostDiscoveryWire.request("""{"version":2,"action":"discover"}""".toByteArray())
        }
        assertThrows(IllegalArgumentException::class.java) {
            USBAccessoryWire.parse("""{"type":"unknown","version":2}""".toByteArray())
        }
        val oversized = USBHostRequest(1, USBHostAction.Connect, "x".repeat(USBHostDiscoveryWire.MAX_MESSAGE_BYTES))
        assertThrows(IllegalArgumentException::class.java) { USBHostDiscoveryWire.frame(oversized) }
    }
}
