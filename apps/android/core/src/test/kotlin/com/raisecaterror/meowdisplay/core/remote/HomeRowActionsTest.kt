package com.raisecaterror.meowdisplay.core.remote

import org.junit.Assert.assertEquals
import org.junit.Test

class HomeRowActionsTest {
    private val saved = RemoteEndpoint("mac.tailnet.ts.net", 9003)

    private fun action(status: MacStatus, nearby: Boolean = false, usb: Boolean = false) =
        HomeRowActions.primary(status, nearby = nearby, usbAvailable = usb)

    @Test
    fun aNearbyMacAsksWhichRouteToUse() {
        assertEquals(HomeRowAction.RouteChoice,
            action(MacStatus.AvailableLocally, nearby = true))
        assertEquals(HomeRowAction.RouteChoice,
            action(MacStatus.NotFound, usb = true))
    }

    @Test
    fun aPairedMacThatIsNotVisibleCanStillBeAskedAgain() {
        assertEquals(HomeRowAction.Connect,
            action(MacStatus.SavedRemote(saved.host)))
        assertEquals(HomeRowAction.Connect,
            action(MacStatus.NotFound))
        assertEquals(HomeRowAction.Retry,
            action(MacStatus.Offline(OfflineReason.TimedOut)))
        assertEquals(HomeRowAction.Retry,
            action(MacStatus.DialBackMissed))
        assertEquals(HomeRowAction.Retry,
            action(MacStatus.MacLocalNetworkBlocked))
    }

    @Test
    fun sessionStatesKeepTheirOwnButton() {
        assertEquals(HomeRowAction.Show, action(MacStatus.Connected(null)))
        assertEquals(HomeRowAction.Cancel,
            action(MacStatus.Connecting(ConnectingStep.WaitingForMac)))
        assertEquals(HomeRowAction.None, action(MacStatus.SwitchedOut, nearby = true))
    }
}
