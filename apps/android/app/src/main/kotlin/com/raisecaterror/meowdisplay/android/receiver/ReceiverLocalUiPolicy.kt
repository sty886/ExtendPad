package com.raisecaterror.meowdisplay.android.receiver

/**
 * Keeps the decoder's Surface alive behind local Home/Settings without letting
 * the hosted desktop show through or receive touches meant for local UI.
 */
internal object ReceiverLocalUiPolicy {
    fun pictureAlpha(immersive: Boolean): Float = if (immersive) 1f else 0f
    fun inputVisible(immersive: Boolean): Boolean = immersive
    fun inputAllowed(immersive: Boolean, controllerAllowed: Boolean): Boolean = immersive && controllerAllowed
}
