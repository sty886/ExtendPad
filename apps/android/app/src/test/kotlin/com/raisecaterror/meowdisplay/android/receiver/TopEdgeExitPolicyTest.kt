package com.raisecaterror.meowdisplay.android.receiver

import com.raisecaterror.meowdisplay.core.controls.CGPoint
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TopEdgeExitPolicyTest {
    @Test
    fun hiddenWithoutHardwarePointer() {
        assertFalse(TopEdgeExitPolicy.shouldShow(null, buttonHovered = false))
    }

    @Test
    fun showsAtTopEdge() {
        assertTrue(TopEdgeExitPolicy.shouldShow(CGPoint(0.5, 0.0), buttonHovered = false))
        assertTrue(TopEdgeExitPolicy.shouldShow(CGPoint(0.5, TopEdgeExitPolicy.TOP_EDGE_NORMALIZED), buttonHovered = false))
    }

    @Test
    fun hidesBelowTopEdge() {
        assertFalse(TopEdgeExitPolicy.shouldShow(CGPoint(0.5, 0.02), buttonHovered = false))
        assertFalse(TopEdgeExitPolicy.shouldShow(CGPoint(0.5, -0.01), buttonHovered = false))
    }

    @Test
    fun hoveringButtonKeepsItAvailable() {
        assertTrue(TopEdgeExitPolicy.shouldShow(null, buttonHovered = true))
        assertTrue(TopEdgeExitPolicy.shouldShow(CGPoint(0.5, 0.5), buttonHovered = true))
    }
}
