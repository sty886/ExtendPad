package com.raisecaterror.meowdisplay.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostsViewportTest {
    @Test
    fun noHostsUsesTheCardsNaturalHeight() {
        assertNull(hostsViewportPx(hostCount = 0, itemHeightsPx = emptyMap(), spacingPx = 30))
    }

    @Test
    fun oneHostFitsExactlyOneItem() {
        assertEquals(120, hostsViewportPx(hostCount = 1, itemHeightsPx = mapOf(0 to 120), spacingPx = 30))
    }

    @Test
    fun twoHostsFitBothItemsAndTheGapBetweenThem() {
        assertEquals(
            270,
            hostsViewportPx(hostCount = 2, itemHeightsPx = mapOf(0 to 120, 1 to 120), spacingPx = 30),
        )
    }

    @Test
    fun moreHostsKeepTheSameTwoItemWindow() {
        // Item three and later are reached by scrolling, not by growing the home.
        assertEquals(
            285,
            hostsViewportPx(hostCount = 5, itemHeightsPx = mapOf(0 to 130, 1 to 125, 2 to 90, 3 to 90, 4 to 90), spacingPx = 30),
        )
    }

    @Test
    fun unmatchedHeightsAreDifferent() {
        // Different hosts can be different heights; the window fits the first two whole items.
        assertEquals(
            275,
            hostsViewportPx(hostCount = 3, itemHeightsPx = mapOf(0 to 150, 1 to 95, 2 to 400), spacingPx = 30),
        )
    }

    @Test
    fun untilTheFirstTwoItemsAreMeasuredTheCardIsUnconstrained() {
        assertNull(hostsViewportPx(hostCount = 2, itemHeightsPx = mapOf(0 to 120), spacingPx = 30))
        assertNull(hostsViewportPx(hostCount = 3, itemHeightsPx = emptyMap(), spacingPx = 30))
    }
}
