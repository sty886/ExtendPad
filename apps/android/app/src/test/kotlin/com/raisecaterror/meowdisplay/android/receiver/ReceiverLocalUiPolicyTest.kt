package com.raisecaterror.meowdisplay.android.receiver

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReceiverLocalUiPolicyTest {
    @Test
    fun pictureIsHiddenWithoutDestroyingItsSurfaceWhenHomeIsOpen() {
        assertEquals(0f, ReceiverLocalUiPolicy.pictureAlpha(immersive = false))
        assertEquals(1f, ReceiverLocalUiPolicy.pictureAlpha(immersive = true))
    }

    @Test
    fun localUiBlocksHostedInputEvenWhenTheHostAllowsControl() {
        assertFalse(ReceiverLocalUiPolicy.inputVisible(immersive = false))
        assertFalse(ReceiverLocalUiPolicy.inputAllowed(immersive = false, controllerAllowed = true))
        assertFalse(ReceiverLocalUiPolicy.inputAllowed(immersive = true, controllerAllowed = false))
        assertTrue(ReceiverLocalUiPolicy.inputVisible(immersive = true))
        assertTrue(ReceiverLocalUiPolicy.inputAllowed(immersive = true, controllerAllowed = true))
    }
}
