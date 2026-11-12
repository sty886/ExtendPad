package com.raisecaterror.meowdisplay.android.ui

/**
 * The height of the scrolling host list: the first two host items plus the gap
 * between them, so the home around the list stays put and the person can scroll
 * the list on its own. One host keeps the list at its own height; null means the
 * rows have not been measured yet (the card then keeps its natural height).
 */
internal fun hostsViewportPx(hostCount: Int, itemHeightsPx: Map<Int, Int>, spacingPx: Int): Int? = when {
    hostCount <= 0 -> null
    hostCount == 1 -> itemHeightsPx[0]
    else -> {
        val first = itemHeightsPx[0]
        val second = itemHeightsPx[1]
        if (first != null && second != null) first + second + spacingPx else null
    }
}
