package com.raisecaterror.meowdisplay.android.session

import com.raisecaterror.meowdisplay.core.session.ReceiverSession
import com.raisecaterror.meowdisplay.core.session.SessionEvent
import kotlinx.coroutines.flow.StateFlow

/**
 * What the receiver surface, its controls, Window mode and Settings need from
 * a session: the session itself (its input gate and requests), the UI state
 * and its events.
 */
interface SessionHost {
    val session: ReceiverSession
    val ui: StateFlow<MediaUiState>

    /** The receiver controls subscribe here: every session event, in order. */
    var controlEvents: ((SessionEvent) -> Unit)?

    /** Per-Mac "Request Control Automatically"; null: never. */
    val inputAutoRequest: InputAutoRequestPrefs?

    /** A Mac's name for the UI ("your Mac" when unknown). */
    fun macName(peerID: String?): String
}
