package com.raisecaterror.meowdisplay.core.pairing

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bounds connections that haven't authenticated yet (Shared/PreAuthSlots.swift). A pairing
 * listener anyone on the network can reach gives each connection one of a few slots until
 * the peer's commitment arrives, which must happen within [DEADLINE_MS]; when every slot is
 * taken, newcomers are closed at once.
 *
 * [perSourceLimit] additionally stops one host from taking every slot: a source address may
 * hold at most that many of them. The source is only an address, never an identity.
 */
class PreAuthSlots(val limit: Int, val perSourceLimit: Int = 2) {
    companion object {
        const val DEADLINE_MS = 10_000L
        const val PAIRING_LIMIT = 4
    }

    private val used = AtomicInteger(0)
    private val bySource = HashMap<Any, Int>()

    val inUse: Int get() = used.get()

    /** A slot to release exactly once, or null when the global or per-source bound is reached. */
    fun tryAcquire(source: Any? = null): Slot? = synchronized(bySource) {
        when {
            used.get() >= limit -> null
            source != null && (bySource[source] ?: 0) >= perSourceLimit -> null
            else -> {
                used.incrementAndGet()
                if (source != null) bySource[source] = (bySource[source] ?: 0) + 1
                Slot(source)
            }
        }
    }

    inner class Slot internal constructor(private val source: Any?) {
        private val released = AtomicBoolean(false)
        fun release() {
            if (!released.compareAndSet(false, true)) return
            synchronized(bySource) {
                used.decrementAndGet()
                if (source != null) {
                    val left = (bySource[source] ?: 1) - 1
                    if (left > 0) bySource[source] = left else bySource.remove(source)
                }
            }
        }
    }
}
