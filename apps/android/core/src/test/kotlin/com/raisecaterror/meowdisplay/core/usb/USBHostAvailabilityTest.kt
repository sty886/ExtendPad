package com.raisecaterror.meowdisplay.core.usb

import com.raisecaterror.meowdisplay.core.remote.HostPlatform
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** USB discovery is the only sign of the cable route; a dead one must stop being offered. */
class USBHostAvailabilityTest {
    private val mac = USBHostAdvertisement(1, "MAC-ID", "Mac", true, HostPlatform.MAC)

    @Test
    fun anAnsweredDiscoverOffersTheHost() {
        val availability = USBHostAvailability()
        assertNull(availability.host.value)
        availability.received(mac)
        assertEquals(mac, availability.host.value)
    }

    @Test
    fun aNewerAdvertisementReplacesTheHostAndResetsTheStreak() {
        val availability = USBHostAvailability(missLimit = 2)
        availability.received(mac)
        availability.missed()
        availability.received(mac.copy(name = "Renamed"))
        availability.missed()
        assertEquals("Renamed answered once, so one miss is not a dead route", "Renamed", availability.host.value?.name)
        availability.missed()
        assertNull(availability.host.value)
    }

    @Test
    fun consecutiveMissesWithdrawTheHost() {
        val availability = USBHostAvailability(missLimit = 3)
        availability.received(mac)
        availability.missed()
        availability.missed()
        assertEquals("churn, not a dead route", mac, availability.host.value)
        availability.missed()
        assertNull(availability.host.value)
    }

    @Test
    fun missesWithoutAHostNeverWithdrawAnything() {
        val availability = USBHostAvailability(missLimit = 1)
        repeat(5) { availability.missed() }
        assertNull(availability.host.value)
        availability.received(mac)
        assertEquals("a late answer still offers the host", mac, availability.host.value)
    }

    @Test
    fun zeroMissLimitStillAllowsRecovery() {
        val availability = USBHostAvailability(missLimit = 0)
        availability.received(mac)
        availability.missed()
        assertNull("a nonsensical limit falls back to one miss", availability.host.value)
        availability.received(mac)
        assertEquals(mac, availability.host.value)
    }

    @Test
    fun clearWithdrawsImmediatelyAndForgetsTheStreak() {
        val availability = USBHostAvailability(missLimit = 3)
        availability.received(mac)
        availability.missed()
        availability.missed()
        availability.clear()
        assertNull(availability.host.value)
        availability.received(mac)
        availability.missed()
        availability.missed()
        assertEquals("the pre-clear misses do not count", mac, availability.host.value)
    }
}
