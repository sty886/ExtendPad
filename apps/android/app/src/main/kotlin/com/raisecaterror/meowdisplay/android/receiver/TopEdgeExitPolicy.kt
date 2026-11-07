package com.raisecaterror.meowdisplay.android.receiver

import com.raisecaterror.meowdisplay.core.controls.CGPoint

/** Shows the receiver's exit control only for a hardware pointer at the top edge. */
internal object TopEdgeExitPolicy {
    /** About 12 dp on an 800-point-tall extended display. */
    const val TOP_EDGE_NORMALIZED = 0.015

    fun shouldShow(pointer: CGPoint?, buttonHovered: Boolean): Boolean =
        buttonHovered || pointer != null && pointer.y in 0.0..TOP_EDGE_NORMALIZED
}
