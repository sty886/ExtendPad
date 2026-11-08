package com.raisecaterror.meowdisplay.core.usb

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Whether a Mac's USB advertisement should still be offered to the person.
 *
 * The ADB-reverse discovery socket (127.0.0.1:9005) is the only sign that the
 * cable route still exists, and it can stop answering without telling us: the
 * cable is unplugged, ExtendPad quits on the Mac, or the adb server restarts.
 * One missed round trip is normal churn (the Mac may be busy); several in a
 * row mean the route is gone. Keeping it on screen after that only produces a
 * "USB connection request failed" dialog when the person taps Connect, so
 * withdraw the host until an advertisement answers again.
 */
class USBHostAvailability(private val missLimit: Int = DEFAULT_MISS_LIMIT) {
    private val state = MutableStateFlow<USBHostAdvertisement?>(null)
    private var misses = 0

    /** The discovered Mac, or null once its discovery route stopped answering. */
    val host: StateFlow<USBHostAdvertisement?> = state.asStateFlow()

    /** A discover round trip was answered: the route works and [advertisement] is current. */
    @Synchronized
    fun received(advertisement: USBHostAdvertisement) {
        misses = 0
        state.value = advertisement
    }

    /** A discover round trip got no answer. The host is withdrawn after [missLimit] in a row. */
    @Synchronized
    fun missed() {
        if (state.value == null) return
        misses += 1
        if (misses >= missLimit.coerceAtLeast(1)) state.value = null
    }

    /** Withdraw the host now and forget the streak (backgrounded, cable gone, request refused). */
    @Synchronized
    fun clear() {
        misses = 0
        state.value = null
    }

    companion object {
        /** Five discover round trips are ~5 s: a route that cannot answer them is gone, not busy. */
        const val DEFAULT_MISS_LIMIT = 5
    }
}
