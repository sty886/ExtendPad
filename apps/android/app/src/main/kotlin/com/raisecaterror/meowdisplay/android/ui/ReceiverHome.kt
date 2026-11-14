package com.raisecaterror.meowdisplay.android.ui

import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Switch
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.material3.OutlinedTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.res.painterResource
import com.raisecaterror.meowdisplay.android.receiver.overlay.GlyphIcon
import com.raisecaterror.meowdisplay.android.receiver.overlay.OverlayGlyph
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import com.raisecaterror.meowdisplay.android.R
import com.raisecaterror.meowdisplay.core.pairing.PairedMacCleanup
import android.content.ClipData
import android.content.ClipboardManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import com.raisecaterror.meowdisplay.android.ui.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.raisecaterror.meowdisplay.android.discovery.Bonjour
import com.raisecaterror.meowdisplay.android.identity.DeviceIdentity
import com.raisecaterror.meowdisplay.android.pairing.PairingController
import com.raisecaterror.meowdisplay.android.remote.RemoteAccess
import com.raisecaterror.meowdisplay.core.remote.HomeRowAction
import com.raisecaterror.meowdisplay.core.remote.HomeRowActions
import com.raisecaterror.meowdisplay.core.remote.HomeRows
import com.raisecaterror.meowdisplay.core.remote.MacFacts
import com.raisecaterror.meowdisplay.core.remote.MacStatus
import com.raisecaterror.meowdisplay.core.remote.MacStatusReducer
import com.raisecaterror.meowdisplay.android.session.MediaController
import com.raisecaterror.meowdisplay.android.session.MediaUiState
import com.raisecaterror.meowdisplay.android.trust.PinStore
import com.raisecaterror.meowdisplay.android.usb.USBAccess
import com.raisecaterror.meowdisplay.core.pairing.PairingClassification
import com.raisecaterror.meowdisplay.core.session.DisplayMode
import com.raisecaterror.meowdisplay.core.session.InputWireState
import com.raisecaterror.meowdisplay.core.session.ReceiverApprovalDecision
import com.raisecaterror.meowdisplay.core.session.SessionPhase

/**
 * Home: the name and one short status line, categorized hosts with an explicit route choice,
 * a quiet row of links (How to Connect, This Device) and Settings & Help. While
 * a session is live this is shown over the running picture, so returning to it is instant.
 */
@Composable
fun ReceiverHome(
    identity: DeviceIdentity,
    pins: PinStore,
    bonjour: Bonjour,
    pairing: PairingController,
    media: MediaController,
    remote: RemoteAccess,
    usb: USBAccess,
    onReturnToDisplay: (() -> Unit)? = null,
    onOpenSettings: (() -> Unit)? = null,
) {
    val ui by pairing.ui.collectAsState()
    val mediaUi by media.ui.collectAsState()
    val nearby by bonjour.nearbyMacs.collectAsState()
    val paired by pins.paired.collectAsState()
    val autoRequestFlow = remember(media) { media.inputAutoRequest?.enabledPeers ?: kotlinx.coroutines.flow.MutableStateFlow(emptySet<String>()) }
    val autoRequestPeers by autoRequestFlow.collectAsState()
    val remoteMacs by remote.store.macs.collectAsState()
    val attempts by remote.coordinator.attempts.collectAsState()
    val usbHost by usb.host.collectAsState()
    val usbPending by usb.pending.collectAsState()
    val usbError by usb.error.collectAsState()
    val macName = { peerID: String? -> paired.firstOrNull { it.peerID == peerID }?.name ?: "your Mac" }
    var showDetails by remember { mutableStateOf(false) }
    var connectionChoiceFor by rememberSaveable { mutableStateOf<String?>(null) }
    var pairChoiceFor by rememberSaveable { mutableStateOf<String?>(null) }
    var policyFor by rememberSaveable { mutableStateOf<String?>(null) }
    var forgetFor by rememberSaveable { mutableStateOf<String?>(null) }
    var cleanupList by remember { mutableStateOf<List<PairedMacCleanup.Entry>>(emptyList()) }
    // Old copies of a Mac: same name as a newer pairing, not connected or nearby (never guessed).
    val oldCopies = {
        PairedMacCleanup.superseded(paired.map { mac ->
            PairedMacCleanup.Entry(mac.peerID, mac.name, mac.pairedAtMillis, inUse = mediaUi.peerID == mac.peerID || remote.nearby(mac.peerID))
        })
    }
    var securityFor by rememberSaveable { mutableStateOf<String?>(null) }
    var showSteps by rememberSaveable { mutableStateOf(false) }
    // Only windows too short for the fixed home (phones in landscape, a tablet in a very
    // short split-screen pane) keep a scrolling page so Settings stays reachable.
    val density = LocalDensity.current
    val windowHeight = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
    val compactHeight = windowHeight < 560.dp
    // Short tablet windows trade the helper copy and some header space for a home
    // that fits without any page scrolling; only the host list moves.
    val tightHome = windowHeight < 700.dp
    // One row per host, regardless of platform or route. A host found over both
    // Wi-Fi and USB remains one row; discovery alone never connects or trusts it.
    val rows = HomeRows.buildFromNearby(paired.map { HomeRows.Paired(it.peerID, it.name) }, nearby.map { HomeRows.Nearby(it.serviceName, it.advert) })
    val toPair = nearby.filter { it.serviceName in rows.toPair }
    // Every paired Mac keeps a row, even while Bonjour cannot see it right now: after a long
    // disconnect the host list could be empty and the only thing left was "Looking for hosts…",
    // with no way to ask for the Mac again. The row's status says whether it is nearby, has a
    // saved remote address, or is simply not found, and its button always has a next step.
    val pairedRows = paired.distinctBy { it.peerID }
    val usbOnly = usbHost?.takeIf { host ->
        paired.none { it.peerID == host.peerID } && nearby.none { (it.advert?.installID ?: it.serviceName) == host.peerID }
    }
    val hostCount = pairedRows.size + toPair.size + if (usbOnly != null) 1 else 0
    val hasNotices = mediaUi.updateMessage != null || ui.message != null || mediaUi.connectFailedFor != null
    // Rows report the height they laid out at, so the card can show exactly two
    // complete host items at any font scale while the home around them stays put.
    val hostItemHeights = remember { mutableStateMapOf<Int, Int>() }
    val hosts: @Composable ColumnScope.() -> Unit = {
        if (hostCount == 0) {
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                if (mediaUi.listening) {
                    CircularProgressIndicator(Modifier.size(16.dp).clearAndSetSemantics {}, strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                }
                Text(
                    if (mediaUi.listening) "Looking for hosts on Wi-Fi and USB…" else "Open ExtendPad to look for hosts.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                // A long idle can leave NsdManager with nothing to report. Let the
                // person ask again instead of waiting forever or restarting the app.
                TextButton(onClick = { pairing.refreshDiscovery() }) { Text("Refresh") }
            }
        }
        pairedRows.forEachIndexed { index, mac ->
            val awaiting = mediaUi.peerID == mac.peerID && mediaUi.awaitingMacApproval
            val live = mediaUi.peerID == mac.peerID && mediaUi.admitted && !awaiting
            val isNearby = remote.nearby(mac.peerID)
            val isUSB = usbHost?.peerID == mac.peerID
            val saved = remoteMacs[mac.peerID]?.endpoint ?: remote.automaticEndpoint(mac.peerID)
            val status = MacStatusReducer.reduce(
                MacFacts(
                    peerID = mac.peerID, name = mac.name, nearby = isNearby, remote = saved, connected = live,
                    route = mediaUi.route.takeIf { live }, awaitingMacApproval = awaiting,
                    localConnectPending = mediaUi.connectingTo == mac.peerID, attempt = attempts[mac.peerID],
                    switchedOut = isNearby && remote.switchedOut(mac.peerID),
                    macLocalNetworkBlocked = isNearby && remote.macLocalNetworkBlocked(mac.peerID),
                ),
            ) { id -> paired.firstOrNull { it.peerID == id }?.name }
            val busy = status is MacStatus.Connecting || status is MacStatus.NeedsMacApproval || usbPending == mac.peerID
            val rowAction = HomeRowActions.primary(status, isNearby, isUSB)
            HostListItem(index, hostItemHeights) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
                MacRow(
                    title = mac.name,
                    subtitle = listOfNotNull(status.text, if (isUSB) "USB available" else null,
                        if (isNearby) "Wi-Fi available" else null, mac.user,
                        "ID " + com.raisecaterror.meowdisplay.core.tls.PinnedTls.shortId(mac.spki))
                        .joinToString(" · "),
                    detail = status.hint,
                    primary = if (usbPending == mac.peerID) "Connecting…" to {} else when (rowAction) {
                        HomeRowAction.RouteChoice -> "Connect" to { connectionChoiceFor = mac.peerID }
                        HomeRowAction.Connect -> "Connect" to { remote.connect(mac.peerID, DisplayMode.Extend) }
                        HomeRowAction.Retry -> "Retry" to { remote.connect(mac.peerID, DisplayMode.Extend) }
                        HomeRowAction.Show -> onReturnToDisplay?.let { "Show" to it }
                        HomeRowAction.Cancel -> "Cancel" to { remote.cancel(mac.peerID) }
                        HomeRowAction.None -> null
                    },
                    enabled = when (rowAction) {
                        HomeRowAction.None -> false
                        HomeRowAction.Show -> onReturnToDisplay != null
                        else -> (mediaUi.listening || live || busy) && usbPending != mac.peerID
                    },
                    menu = buildList {
                        if (!live && !busy) {
                            if (isUSB) {
                                add("USB: Mirror" to { usb.connect(mac.peerID, DisplayMode.Mirror) })
                                add("USB: Extend" to { usb.connect(mac.peerID, DisplayMode.Extend) })
                            }
                            if (isNearby) {
                                add("Wi-Fi: Mirror" to { remote.connect(mac.peerID, DisplayMode.Mirror) })
                                add("Wi-Fi: Extend" to { remote.connect(mac.peerID, DisplayMode.Extend) })
                            }
                        }
                        media.inputAutoRequest?.let { auto ->
                            val on = mac.peerID in autoRequestPeers
                            add((if (on) "Request Control Automatically: On" else "Request Control Automatically: Off") to { auto.setEnabled(mac.peerID, !on) })
                        }
                        add("Connection Requests…" to { policyFor = mac.peerID })
                        add("Security Details" to { securityFor = mac.peerID })
                        add("Forget This Mac…" to { forgetFor = mac.peerID })
                    },
                )
            }
        }
        val old = oldCopies()
        if (old.isNotEmpty()) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
            TextButton(onClick = { cleanupList = old }) {
                Text("Clean Up ${old.size} Old ${if (old.size == 1) "Entry" else "Entries"}…")
            }
        }
        toPair.forEachIndexed { index, mac ->
            val switchedOut = mac.advert?.switchedOut == true
            val key = mac.advert?.installID ?: mac.serviceName
            val hasUSB = usbHost?.peerID == key
            HostListItem(pairedRows.size + index, hostItemHeights) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
                MacRow(
                    title = mac.advert?.sessionTitle ?: mac.serviceName,
                    subtitle = if (switchedOut) "Switched Out" else "Not paired" + (if (hasUSB) " · USB available" else ""),
                    primary = if (switchedOut) null else "Pair" to { pairChoiceFor = key },
                    enabled = ui.pairingWith == null && usbPending == null, menu = emptyList(),
                )
            }
        }
        usbOnly?.let { host ->
            HostListItem(pairedRows.size + toPair.size, hostItemHeights) {
                HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.5f))
                MacRow(
                    title = host.name, subtitle = "Not paired · USB available",
                    primary = "Pair" to { pairChoiceFor = host.peerID },
                    enabled = ui.pairingWith == null && usbPending == null, menu = emptyList(),
                )
            }
        }
    }

    Surface(color = MaterialTheme.colorScheme.background, modifier = Modifier.fillMaxSize()) {
      // Same arrangement as the iPhone: centred logo, name and one status line on top, the Macs
      // card, then the links and Settings & Help at the bottom centre, always in reach.
      Column(Modifier.fillMaxSize().safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (compactHeight) {
          // A phone in landscape cannot hold the fixed home together with the links and
          // Settings, so that one narrow case keeps a scrolling page.
          LazyColumn(
              modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = 20.dp),
              horizontalAlignment = Alignment.CenterHorizontally,
              verticalArrangement = Arrangement.spacedBy(if (tightHome) 8.dp else 12.dp),
          ) {
              item { HomeHeader(tight = true) }
              item { HomeSessionStatus(mediaUi, macName, onReturnToDisplay, onOpenSettings, tight = true) { media.session.disconnect() } }
              if (hasNotices) item { HomeNotices(mediaUi, ui.message, pairing::dismissMessage, macName, media::dismissConnectFailure, tight = true) }
              item { HostsCard(hostCount, hostItemHeights, tight = true, content = hosts) }
              item { FooterLinks(onSteps = { showSteps = true }, onDevice = { showDetails = true }) }
          }
        } else {
          // The home is fixed: only the rows inside the host card scroll, so the app icon,
          // status, links and Settings never move.
          Column(
              Modifier.weight(1f).fillMaxWidth().padding(horizontal = 20.dp).clipToBounds(),
              horizontalAlignment = Alignment.CenterHorizontally,
              verticalArrangement = Arrangement.spacedBy(if (tightHome) 8.dp else 12.dp),
          ) {
              HomeHeader(tight = tightHome)
              HomeSessionStatus(mediaUi, macName, onReturnToDisplay, onOpenSettings, tight = tightHome) { media.session.disconnect() }
              HomeNotices(mediaUi, ui.message, pairing::dismissMessage, macName, media::dismissConnectFailure, tight = tightHome)
              HostsCard(hostCount, hostItemHeights, tight = tightHome, content = hosts)
          }
          FooterLinks(onSteps = { showSteps = true }, onDevice = { showDetails = true },
              modifier = Modifier.padding(horizontal = 20.dp))
        }
        onOpenSettings?.let { open ->
            OutlinedButton(onClick = open, modifier = Modifier.padding(top = 4.dp, bottom = 16.dp)) {
                GlyphIcon(OverlayGlyph.Gear, 18.dp, MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(8.dp))
                Text("Settings & Help")
            }
        }
      }
    }

    if (showSteps) {
        AlertDialog(
            onDismissRequest = { showSteps = false },
            title = { Text("How to Connect") },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) { Steps() } },
            confirmButton = { TextButton(onClick = { showSteps = false }) { Text("Done") } },
        )
    }

    if (showDetails) DeviceDetails(identity.fingerprint, remote) { showDetails = false }

    connectionChoiceFor?.let { peerID ->
        val mac = paired.firstOrNull { it.peerID == peerID }
        if (mac != null) RouteChoiceDialog(
            title = "Connect to ${mac.name}", action = "Connect",
            wifiAvailable = remote.nearby(peerID), usbAvailable = usbHost?.peerID == peerID,
            onWiFi = { remote.connect(peerID, DisplayMode.Extend); connectionChoiceFor = null },
            onUSB = { usb.connect(peerID, DisplayMode.Extend); connectionChoiceFor = null },
            onDismiss = { connectionChoiceFor = null },
        )
    }

    pairChoiceFor?.let { key ->
        val wifiMac = nearby.firstOrNull { (it.advert?.installID ?: it.serviceName) == key }
        val host = usbHost?.takeIf { it.peerID == key }
        RouteChoiceDialog(
            title = "Pair with ${host?.name ?: wifiMac?.advert?.sessionTitle ?: wifiMac?.serviceName ?: "Mac"}", action = "Pair",
            wifiAvailable = wifiMac != null, usbAvailable = host != null,
            onWiFi = { wifiMac?.let(pairing::pair); pairChoiceFor = null },
            onUSB = { host?.let { usb.pair(it.peerID) }; pairChoiceFor = null },
            onDismiss = { pairChoiceFor = null },
        )
    }

    usbError?.let { message ->
        AlertDialog(
            onDismissRequest = usb::dismissError, title = { Text("USB") }, text = { Text(message) },
            confirmButton = { TextButton(onClick = usb::dismissError) { Text("Done") } },
        )
    }

    policyFor?.let { peerID ->
        val changes by media.connectionPolicyChanges.collectAsState()
        ConnectionPolicyDialog(media.macName(peerID), media.connectionPolicy(peerID).also { changes }, media.automaticallyAllowConnections,
            onChoose = { media.setConnectionPolicy(peerID, it); policyFor = null }, onDismiss = { policyFor = null })
    }
    forgetFor?.let { peerID ->
        AlertDialog(
            onDismissRequest = { forgetFor = null },
            title = { Text("Forget \u201C${media.macName(peerID)}\u201D?") },
            text = { Text("This removes the pairing and its saved address. To use this Mac again, pair it again.", Modifier.verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton(onClick = { remote.forget(peerID); forgetFor = null }) { Text("Forget", color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { forgetFor = null }) { Text("Cancel") } },
        )
    }
    if (cleanupList.isNotEmpty()) {
        val format = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
        AlertDialog(
            onDismissRequest = { cleanupList = emptyList() },
            title = { Text("Remove ${cleanupList.size} old ${if (cleanupList.size == 1) "entry" else "entries"}?") },
            text = {
                Text(cleanupList.joinToString("\n") { e ->
                    e.name + (e.pairedAtMillis?.let { " · paired " + format.format(java.util.Date(it)) } ?: " · paired before dates were kept")
                }, Modifier.verticalScroll(rememberScrollState()))
            },
            confirmButton = {
                TextButton(onClick = {
                    // Only what is still an old copy now (a Mac may have connected meanwhile).
                    val still = oldCopies().map { it.id }.toSet()
                    cleanupList.filter { it.id in still }.forEach { remote.forget(it.id) }
                    cleanupList = emptyList()
                }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { cleanupList = emptyList() }) { Text("Cancel") } },
        )
    }
    securityFor?.let { peerID ->
        val mac = paired.firstOrNull { it.peerID == peerID }
        if (mac == null) securityFor = null else SecurityDetailsDialog(
            mac, remoteMacs[peerID]?.endpoint,
            remote.store.sharedWith(peerID).mapNotNull { other -> paired.firstOrNull { it.peerID == other }?.name },
        ) { securityFor = null }
    }

    mediaUi.approval?.let { approval ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text("Show ${macName(approval.peerID)} here?") },
            text = {
                Text(
                    "It wants to " + when (approval.mode) {
                        DisplayMode.Mirror -> "mirror its screen"
                        DisplayMode.Window -> "show its windows"
                        else -> "extend its desktop"
                    } + " on this device. It can't control anything here, and this device can't control it unless you ask.",
                    Modifier.verticalScroll(rememberScrollState()),
                )
            },
            confirmButton = { TextButton(onClick = { media.answer(approval.id, ReceiverApprovalDecision.Allow) }) { Text("Allow") } },
            dismissButton = { TextButton(onClick = { media.answer(approval.id, ReceiverApprovalDecision.RejectForSession) }) { Text("Not Now") } },
        )
    }

    ui.prompt?.let { prompt ->
        AlertDialog(
            onDismissRequest = {},
            title = {
                Text(
                    when (prompt.classification) {
                        PairingClassification.NewPeer -> "Pair with ${prompt.peerName}?"
                        PairingClassification.RePairSameKey -> "Pair again with ${prompt.peerName}?"
                        PairingClassification.IdentityChanged -> "${prompt.peerName} has a new identity"
                    },
                )
            },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Make sure ${prompt.peerName} shows the same code:")
                    Text(
                        prompt.sas, fontSize = 40.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.semantics { contentDescription = "配对验证码：" + prompt.sas.toCharArray().joinToString(" ") },
                    )
                    // The name is self-chosen; this ID comes from the peer's
                    // actual TLS public key, so a spoofed name is not the
                    // only thing the person can check.
                    Text("Device ID ${prompt.shortID}", style = MaterialTheme.typography.bodySmall)
                    if (prompt.classification == PairingClassification.IdentityChanged) {
                        Text("Only continue if you reinstalled ExtendPad on that Mac or reset it. Otherwise, cancel.", style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = { TextButton(onClick = { pairing.answer(true) }) { Text("Codes Match") } },
            dismissButton = { TextButton(onClick = { pairing.cancel() }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun ConnectedCard(mac: String, ui: MediaUiState, onReturn: () -> Unit, onSettings: (() -> Unit)?, onDisconnect: () -> Unit, tight: Boolean = false) {
    var confirm by remember { mutableStateOf(false) }
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
        modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth(),
    ) {
        Column(
            Modifier.padding(if (tight) 12.dp else 16.dp),
            verticalArrangement = Arrangement.spacedBy(if (tight) 6.dp else 8.dp),
        ) {
            // One reading for the status, spoken again when it changes (for example when control is granted).
            Column(Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }) {
                Text("Connected to $mac", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onPrimaryContainer)
                val source = when (ui.source) {
                    "mirror" -> "Mirror"
                    "extend" -> "Extend"
                    "window" -> "Windows"
                    else -> "Showing the Mac"
                }
                val control = if (ui.input == InputWireState.Allowed) "Controlling" else "View Only"
                Text(
                    listOfNotNull(source, control, ui.route?.sessionLabel).joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onReturn) { Text("Return to Display") }
                onSettings?.let { OutlinedButton(onClick = it) { Text("Settings") } }
            }
            TextButton(onClick = { confirm = true }) { Text("Disconnect") }
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Disconnect from $mac?") },
            text = { Text("The picture closes on this device. Connect again from here any time.", Modifier.verticalScroll(rememberScrollState())) },
            confirmButton = { TextButton(onClick = { confirm = false; onDisconnect() }) { Text("Disconnect") } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun Steps() {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        com.raisecaterror.meowdisplay.android.receiver.connectionHelp.forEach { (title, body) ->
            Column {
                Text(title, style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** This device's identity. The key fingerprint isn't secret, but it stays hidden until asked for (C4 F-03). */
@Composable
private fun DeviceDetails(fingerprint: String, remote: RemoteAccess, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var revealed by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("This Device") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                var name by remember { mutableStateOf(DeviceIdentity.customName(context) ?: "") }
                OutlinedTextField(
                    name, { name = it.take(40) }, label = { Text("Device Name") }, singleLine = true,
                    placeholder = { Text(DeviceIdentity.systemName(context)) },
                    supportingText = { Text("Shown on your Mac. Macs see a new name the next time they find this device.") },
                    keyboardActions = KeyboardActions(onDone = { DeviceIdentity.setCustomName(context, name) }),
                    modifier = Modifier.fillMaxWidth(),
                )
                if ((DeviceIdentity.customName(context) ?: "") != name.trim()) {
                    TextButton(onClick = { DeviceIdentity.setCustomName(context, name) }) { Text("Save Name") }
                }
                Text("Security key", style = MaterialTheme.typography.labelLarge, modifier = Modifier.semantics { heading() })
                Text(
                    if (revealed) fingerprint.chunked(4).joinToString(" ") else "Hidden",
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.semantics { contentDescription = if (revealed) "Security key fingerprint $fingerprint" else "Security key hidden" },
                )
                Text("Macs pin this key when you pair. You only need it to check a pairing by hand.", style = MaterialTheme.typography.bodySmall)
                var automatic by remember { mutableStateOf(remote.automaticEnabled) }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(
                        value = automatic, role = Role.Switch,
                        onValueChange = { on -> remote.automaticEnabled = on; automatic = on },
                    ),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Share Tailscale Addresses with Paired Macs", Modifier.weight(1f))
                    Switch(checked = automatic, onCheckedChange = null)
                }
                Text(
                    "After a connection, this device and the Mac tell each other their Tailscale addresses, so Remote Access " +
                        "can reach the Mac later without typing one. Only addresses are shared. They never grant trust: every " +
                        "connection still needs the existing secure pairing. Turning this off forgets the addresses Macs shared.",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (copied) Text("Copied.", style = MaterialTheme.typography.bodySmall, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            }
        },
        confirmButton = {
            Row {
                TextButton(
                    onClick = { revealed = !revealed },
                    modifier = Modifier.semantics { contentDescription = if (revealed) "Hide security key" else "Reveal security key" },
                ) { Text(if (revealed) "Hide" else "Reveal") }
                if (revealed) TextButton(onClick = {
                    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("ExtendPad key", fingerprint))
                    copied = true
                }, modifier = Modifier.semantics { contentDescription = "Copy security key" }) { Text("Copy") }
                TextButton(onClick = onDismiss) { Text("Done") }
            }
        },
    )
}

/** One short line for the home screen and Settings. What to do about a state is in How to Connect. */
internal fun sessionStatus(ui: MediaUiState, mac: String): String = when (ui.phase) {
    SessionPhase.Connected -> when {
        ui.awaitingMacApproval -> "Waiting for $mac to accept"
        ui.admitted -> "Connected to $mac"
        else -> "Connecting to $mac…"
    }
    SessionPhase.Connecting -> "Connecting to $mac…"
    SessionPhase.Paused -> "Paused by $mac"
    SessionPhase.Reconnecting -> "Reconnecting to $mac…"
    SessionPhase.ReconnectFailed -> "Connection to $mac lost"
    SessionPhase.Unrecoverable -> "Update ExtendPad to use $mac"
    SessionPhase.PeerDisconnected -> "$mac ended the session"
    SessionPhase.Disconnected -> ui.listenerError ?: if (ui.listening) "Ready to connect" else "Not available in the background"
}

@Composable
private fun HostsCard(
    hostCount: Int,
    itemHeightsPx: Map<Int, Int>,
    tight: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val density = LocalDensity.current
    val gap = if (tight) 8.dp else 10.dp
    // Exactly two whole host items (plus the gap between them) stay visible; the
    // rest of the list scrolls inside the card without moving the rest of the home.
    val viewportPx = hostsViewportPx(hostCount, itemHeightsPx, with(density) { gap.roundToPx() })
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth()) {
        Column(
            Modifier.padding(horizontal = 16.dp, vertical = if (tight) 12.dp else 16.dp),
            verticalArrangement = Arrangement.spacedBy(if (tight) 8.dp else 10.dp),
        ) {
            Text(
                "Available Hosts", style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.semantics { heading() },
            )
            if (!tight) {
                Text(
                    "Choose an available computer as this tablet's display source.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "Select a host, then choose USB or Wi-Fi. Discovery alone never connects.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Column(
                Modifier.fillMaxWidth().then(
                    when {
                        viewportPx != null -> Modifier.height(with(density) { viewportPx.toDp() })
                        // Until the rows are measured, keep the card from stretching the page.
                        hostCount > 0 -> Modifier.heightIn(max = 220.dp)
                        else -> Modifier
                    }
                ).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(gap),
            ) { content() }
        }
    }
}

/** One measured host item, so [HostsCard] knows where two complete items end. */
@Composable
private fun HostListItem(index: Int, heightsPx: MutableMap<Int, Int>, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().onSizeChanged { heightsPx[index] = it.height },
        content = content,
    )
}

/** Logo and name, fixed at the top of a tablet home. */
@Composable
private fun HomeHeader(tight: Boolean = false) {
    Column(Modifier.widthIn(max = 640.dp).fillMaxWidth().padding(top = if (tight) 8.dp else 20.dp, bottom = if (tight) 0.dp else 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Image(painterResource(R.drawable.meow_logo), contentDescription = null, modifier = Modifier.size(if (tight) 56.dp else 72.dp))
        Spacer(Modifier.height(if (tight) 4.dp else 8.dp))
        Text("ExtendPad", style = if (tight) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.semantics { heading() })
    }
}

/** The one status line under the name, or the connected card while a session is up. */
@Composable
private fun HomeSessionStatus(
    mediaUi: MediaUiState,
    macName: (String?) -> String,
    onReturnToDisplay: (() -> Unit)?,
    onOpenSettings: (() -> Unit)?,
    tight: Boolean = false,
    onDisconnect: () -> Unit,
) {
    if (onReturnToDisplay != null && mediaUi.admitted && !mediaUi.awaitingMacApproval) {
        ConnectedCard(macName(mediaUi.peerID), mediaUi, onReturnToDisplay, onOpenSettings, onDisconnect, tight)
    } else {
        Hint(sessionStatus(mediaUi, macName(mediaUi.peerID)), centered = true, live = true)   // under the name, as on iPhone
    }
}

/** Transient messages; emits nothing when there is none. */
@Composable
private fun HomeNotices(
    mediaUi: MediaUiState,
    pairingMessage: String?,
    onDismissPairingMessage: () -> Unit,
    macName: (String?) -> String,
    onDismissConnectFailure: () -> Unit,
    tight: Boolean = false,
) {
    if (mediaUi.updateMessage == null && pairingMessage == null && mediaUi.connectFailedFor == null) return
    Column(verticalArrangement = Arrangement.spacedBy(if (tight) 8.dp else 12.dp)) {
        mediaUi.updateMessage?.let { message -> Hint(message, live = true) }
        pairingMessage?.let { message -> Notice(message, onDismiss = onDismissPairingMessage) }
        mediaUi.connectFailedFor?.let { peer ->
            Notice("${macName(peer)} didn't connect. Open ExtendPad on it and check that both are on the same Wi-Fi.",
                onDismiss = onDismissConnectFailure)
        }
    }
}

/** How to Connect · This Device: quiet text links under the card. */
@Composable
private fun FooterLinks(onSteps: () -> Unit, onDevice: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier.widthIn(max = 640.dp).fillMaxWidth(),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onSteps, modifier = Modifier.weight(1f, fill = false)) { Text("How to Connect", textAlign = TextAlign.Center) }
        Text("·", color = MaterialTheme.colorScheme.outline, modifier = Modifier.clearAndSetSemantics {})
        TextButton(onClick = onDevice, modifier = Modifier.weight(1f, fill = false)) { Text("This Device", textAlign = TextAlign.Center) }
    }
}

@Composable
private fun Hint(text: String, centered: Boolean = false, live: Boolean = false) {
    // Connecting, connected, connection lost: these change without a touch, so a screen reader says them (once, politely).
    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth().then(if (live) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier),
        textAlign = if (centered) androidx.compose.ui.text.style.TextAlign.Center else null)
}

@Composable
private fun Notice(text: String, onDismiss: () -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant), modifier = Modifier.widthIn(max = 640.dp).fillMaxWidth()) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite }, color = MaterialTheme.colorScheme.onSurface)
            TextButton(onClick = onDismiss) { Text("OK") }
        }
    }
}

@Composable
private fun RouteChoiceDialog(
    title: String, action: String, wifiAvailable: Boolean, usbAvailable: Boolean,
    onWiFi: () -> Unit, onUSB: () -> Unit, onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Choose the connection method. ExtendPad will not switch it automatically.")
                if (usbAvailable) Button(onClick = onUSB, modifier = Modifier.fillMaxWidth()) { Text("$action via USB") }
                if (wifiAvailable) Button(onClick = onWiFi, modifier = Modifier.fillMaxWidth()) { Text("$action via Wi-Fi") }
                if (!usbAvailable && !wifiAvailable) Text("This host is no longer available.")
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** One Mac in the card: name and one-word subtitle, a prominent action, and a ••• menu for the rest. */
@Composable
private fun MacRow(
    title: String, subtitle: String?, primary: Pair<String, () -> Unit>?, enabled: Boolean, menu: List<Pair<String, () -> Unit>>,
    detail: String? = null,
) {
    var open by remember { mutableStateOf(false) }
    // Large font scales stack the buttons under the name instead of squeezing the name.
    val stacked = LocalDensity.current.fontScale >= 1.5f
    val name: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier.semantics(mergeDescendants = true) {}) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            subtitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
    val actions: @Composable () -> Unit = {
        primary?.let { (label, action) ->
            Button(
                onClick = action, enabled = enabled,
                modifier = Modifier.semantics { contentDescription = "${ChineseText.translate(label)}，$title" },
            ) { Text(label) }
        }
        if (menu.isNotEmpty()) {
            Box {
                TextButton(onClick = { open = true }, modifier = Modifier.semantics { contentDescription = "$title 的更多操作" }) { Text("•••") }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    menu.forEach { (label, action) -> DropdownMenuItem(text = { Text(label) }, onClick = { open = false; action() }) }
                }
            }
        }
    }
    if (stacked) {
        Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
            name(Modifier.fillMaxWidth())
            Row(verticalAlignment = Alignment.CenterVertically) { actions() }
        }
    } else {
        Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            name(Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            actions()
        }
    }
}


/** iOS per-Mac "Connection Requests": Default follows Automatically Allow Connections. */
@Composable
private fun ConnectionPolicyDialog(
    mac: String, current: com.raisecaterror.meowdisplay.core.session.PeerSessionPolicy?, automaticallyAllow: Boolean,
    onChoose: (com.raisecaterror.meowdisplay.core.session.PeerSessionPolicy?) -> Unit, onDismiss: () -> Unit,
) {
    val options = listOf(
        null to (if (automaticallyAllow) "Default (Allow)" else "Default (Ask)"),
        com.raisecaterror.meowdisplay.core.session.PeerSessionPolicy.AlwaysAllow to "Always Allow",
        com.raisecaterror.meowdisplay.core.session.PeerSessionPolicy.Blocked to "Blocked",
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Connection Requests") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("When $mac asks to start a session on this device.", style = MaterialTheme.typography.bodyMedium)
                options.forEach { (policy, label) ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(selected = current == policy, role = Role.RadioButton) { onChoose(policy) }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        androidx.compose.material3.RadioButton(selected = current == policy, onClick = null)
                        Spacer(Modifier.width(8.dp))
                        Text(label)
                    }
                }
                Text("Blocked ends any session with this Mac now and declines its requests until you change this.", style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}
