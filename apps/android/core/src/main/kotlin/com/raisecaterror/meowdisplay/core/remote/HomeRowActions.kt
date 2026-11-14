package com.raisecaterror.meowdisplay.core.remote

/** What a paired Mac's primary home button does. */
enum class HomeRowAction {
    /** Nearby over Wi-Fi or USB: ask which route to use. */
    RouteChoice,
    /** Not nearby: knock the saved address, or send the local connect request (the Mac dials us). */
    Connect,
    /** The last attempt failed: try the same Mac again. */
    Retry,
    Show,
    Cancel,
    None,
}

/**
 * The primary button for a paired Mac, including one that is not on this network right now.
 *
 * A paired Mac used to be rendered only while Bonjour (or USB) saw it. After a long disconnect
 * that left discovery with no results, the home showed only "Looking for hosts…", so there was
 * no way to retry a Mac that was paired but temporarily invisible. The status reducer already
 * decides whether a Mac is nearby, has a saved remote address, or is simply not found; a paired
 * Mac can always be asked again, either through its saved address or through the local connect
 * request the Mac answers by dialing this device.
 */
object HomeRowActions {
    fun primary(status: MacStatus, nearby: Boolean, usbAvailable: Boolean): HomeRowAction = when {
        status.action == RowAction.Show -> HomeRowAction.Show
        status.action == RowAction.Cancel -> HomeRowAction.Cancel
        status.action == RowAction.None -> HomeRowAction.None
        nearby || usbAvailable -> HomeRowAction.RouteChoice
        status.action == RowAction.Connect -> HomeRowAction.Connect
        status.action == RowAction.Retry -> HomeRowAction.Retry
        else -> HomeRowAction.None
    }
}
