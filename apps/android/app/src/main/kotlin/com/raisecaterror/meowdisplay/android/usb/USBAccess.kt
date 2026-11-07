package com.raisecaterror.meowdisplay.android.usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import com.raisecaterror.meowdisplay.android.session.MediaController
import com.raisecaterror.meowdisplay.core.session.DisplayMode
import com.raisecaterror.meowdisplay.core.usb.USBAccessoryMessage
import com.raisecaterror.meowdisplay.core.usb.USBAccessoryRelay
import com.raisecaterror.meowdisplay.core.usb.USBAccessoryWire
import com.raisecaterror.meowdisplay.core.usb.USBHostAction
import com.raisecaterror.meowdisplay.core.usb.USBHostAdvertisement
import com.raisecaterror.meowdisplay.core.usb.USBHostDiscoveryWire
import com.raisecaterror.meowdisplay.core.usb.USBHostRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.DataInputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer

/**
 * USB support, in two transports:
 *
 * 1. **AOA (Android Open Accessory)** — the Mac is the host, switches the tablet
 *    into accessory mode, and the system hands this app the bulk-endpoint
 *    streams. A v2 control channel (USBAccessoryWire) carries Discover/Connect/
 *    Pair and a `relay{port}` command; the app then splices the accessory bytes
 *    to its own pinned TLS (9001) or pairing (9002) listener. No adb, no
 *    developer options.
 *
 * 2. **ADB fallback** — the original ADB-reverse discovery socket
 *    (127.0.0.1:9005, USBHostDiscoveryWire v1). Some OEM firmwares accept AOA
 *    GET_PROTOCOL/SEND_STRING/ACCESSORY_START but never re-enumerate as an
 *    accessory (measured on the Huawei MRX-W39); those devices keep working
 *    through the authorized adb tunnel.
 *
 * Trust is identical in both: AOA/ADB are untrusted byte pipes; the Mac still
 * dials the pinned mutual-TLS listener. This class only moves bytes and hints.
 */
class USBAccess(
    private val context: Context,
    private val media: MediaController,
    /** This app's install id, an unauthenticated hint; TLS pinning still decides. */
    private val localID: () -> String,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val usb = context.getSystemService(UsbManager::class.java)
    private val currentHost = MutableStateFlow<USBHostAdvertisement?>(null)
    private val pendingMac = MutableStateFlow<String?>(null)
    private val lastError = MutableStateFlow<String?>(null)

    val host: StateFlow<USBHostAdvertisement?> = currentHost.asStateFlow()
    val pending: StateFlow<String?> = pendingMac.asStateFlow()
    val error: StateFlow<String?> = lastError.asStateFlow()

    private class Link(
        val accessory: UsbAccessory,
        val input: InputStream,
        val output: OutputStream,
    )

    private val writeLock = Any()
    @Volatile private var link: Link? = null
    private var readerJob: Job? = null
    private var accessoryDiscoverJob: Job? = null
    private var adbDiscoverJob: Job? = null
    @Volatile private var relay: Relay? = null
    @Volatile private var foreground = false
    private var receiverRegistered = false

    /** One raw AOA relay to a local listener (TLS 9001 or pairing 9002). */
    private inner class Relay(val port: Int, val socket: Socket, val writer: Job) {
        @Volatile var closed = false
        fun close() {
            if (closed) return
            closed = true
            runCatching { writer.cancel() }
            runCatching { socket.close() }
        }
    }

    private val permissionAction = "${context.packageName}.usb.AOA_PERMISSION"
    private val permissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == permissionAction) openAttachedAccessory()
        }
    }

    init {
        scope.launch {
            media.ui.collect { ui -> if (ui.admitted) pendingMac.value = null }
        }
        registerPermissionReceiver()
    }

    private fun registerPermissionReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(permissionAction)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(permissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(permissionReceiver, filter)
        }
        receiverRegistered = true
    }

    /** The system launched/focused us for an accessory attach. */
    fun onAccessoryAttached() {
        openAttachedAccessory()
    }

    fun onAccessoryDetached() {
        closeLink()
    }

    fun onForeground() {
        foreground = true
        openAttachedAccessory()
        startAccessoryDiscovering()
        startAdbDiscovering()
    }

    fun onBackground() {
        foreground = false
        accessoryDiscoverJob?.cancel()
        accessoryDiscoverJob = null
        adbDiscoverJob?.cancel()
        adbDiscoverJob = null
        closeLink()
        currentHost.value = null
        pendingMac.value = null
    }

    fun connect(peerID: String, mode: DisplayMode? = null) {
        if (pendingMac.value != null) return
        lastError.value = null
        pendingMac.value = peerID
        media.markRemoteConnect(peerID, mode)
        val sent = if (link != null) {
            sendAOA(USBHostRequest(USBAccessoryWire.VERSION, USBHostAction.Connect, peerID, localID()))
        } else {
            adbRequest(USBHostRequest(USBHostDiscoveryWire.VERSION, USBHostAction.Connect, peerID, localID())) != null
        }
        if (!sent) {
            pendingMac.value = null
            media.clearRemoteConnect(peerID)
            if (link == null) lastError.value = "USB connection request failed. Check the cable and that the Mac app is open."
            return
        }
        scope.launch {
            delay(30_000)
            if (pendingMac.compareAndSet(peerID, null)) media.clearRemoteConnect(peerID)
        }
    }

    fun pair(peerID: String) {
        if (pendingMac.value != null) return
        lastError.value = null
        pendingMac.value = peerID
        val sent = if (link != null) {
            sendAOA(USBHostRequest(USBAccessoryWire.VERSION, USBHostAction.Pair, peerID, localID()))
        } else {
            adbRequest(USBHostRequest(USBHostDiscoveryWire.VERSION, USBHostAction.Pair, peerID, localID())) != null
        }
        if (!sent) {
            pendingMac.value = null
            lastError.value = "USB pairing request failed. Check the cable and that the Mac app is open."
        }
    }

    fun dismissError() { lastError.value = null }

    // MARK: - ADB fallback (legacy discovery socket)

    private fun startAdbDiscovering() {
        adbDiscoverJob?.cancel()
        adbDiscoverJob = scope.launch {
            while (isActive) {
                if (foreground && link == null) {
                    val found = adbRequest(
                        USBHostRequest(USBHostDiscoveryWire.VERSION, USBHostAction.Discover, null, localID())
                    )
                    if (found != null && link == null) {
                        if (currentHost.value?.peerID != found.peerID) Log.i(TAG, "ADB discovery: ${found.name} paired=${found.paired}")
                        currentHost.value = found
                    }
                    delay(if (found == null) 1_000 else 2_000)
                } else {
                    delay(2_000)
                }
            }
        }
    }

    /** The original v1 request/response round trip through adb's reverse tunnel. Null = host unavailable. */
    private fun adbRequest(request: USBHostRequest): USBHostAdvertisement? = try {
        Socket().use { socket ->
            // IPv4 explicitly: adb's reverse listener is 127.0.0.1; getLoopbackAddress()
            // can resolve to ::1, where nothing is listening.
            socket.connect(InetSocketAddress(InetAddress.getByName("127.0.0.1"), USBHostDiscoveryWire.PORT), 1_200)
            socket.soTimeout = 1_200
            socket.outputStream.write(USBHostDiscoveryWire.frame(request))
            socket.outputStream.flush()
            val input = DataInputStream(socket.inputStream)
            val header = ByteArray(4)
            input.readFully(header)
            val length = ByteBuffer.wrap(header).int
            if (length !in 1..USBHostDiscoveryWire.MAX_MESSAGE_BYTES) throw IllegalArgumentException("Invalid USB response")
            val body = ByteArray(length)
            input.readFully(body)
            USBHostDiscoveryWire.advertisement(body)
        }
    } catch (e: Exception) {
        Log.d(TAG, "USB host unavailable over ADB: ${e.message}")
        null
    }

    // MARK: - AOA accessory

    private fun openAttachedAccessory() {
        if (!foreground) return
        val accessories = usb.accessoryList.orEmpty()
        val accessory = accessories.firstOrNull { it.matchesExtendPad() }
            ?: accessories.singleOrNull()
            ?: return
        if (link?.accessory == accessory) return
        closeLink()
        if (!usb.hasPermission(accessory)) {
            val intent = PendingIntent.getBroadcast(
                context, 0, Intent(permissionAction).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            usb.requestPermission(accessory, intent)
            return
        }
        val descriptor = usb.openAccessory(accessory) ?: run {
            lastError.value = "Android didn't open the USB accessory. Unplug and reconnect the cable."
            return
        }
        val opened = Link(accessory, FileInputStream(descriptor.fileDescriptor), FileOutputStream(descriptor.fileDescriptor))
        link = opened
        lastError.value = null
        Log.i(TAG, "AOA accessory opened: ${accessory.manufacturer}/${accessory.model}")
        startReader(opened)
        sendAOA(USBHostRequest(USBAccessoryWire.VERSION, USBHostAction.Discover, null, localID()))
    }

    private fun closeLink() {
        relay?.close(); relay = null
        readerJob?.cancel(); readerJob = null
        runCatching { link?.input?.close() }
        runCatching { link?.output?.close() }
        link = null
        currentHost.value = null
    }

    private fun UsbAccessory.matchesExtendPad(): Boolean =
        manufacturer.equals("ExtendPad", ignoreCase = true) &&
            model.equals("ExtendPad", ignoreCase = true)

    private fun startAccessoryDiscovering() {
        accessoryDiscoverJob?.cancel()
        accessoryDiscoverJob = scope.launch {
            while (isActive) {
                if (foreground && link != null && currentHost.value == null) {
                    sendAOA(USBHostRequest(USBAccessoryWire.VERSION, USBHostAction.Discover, null, localID()))
                }
                delay(2_000)
            }
        }
    }

    private fun sendAOA(request: USBHostRequest): Boolean = sendAccessoryFrame(USBAccessoryWire.frame(request))

    private fun sendAccessoryFrame(frame: ByteArray): Boolean {
        val output = link?.output ?: return false
        return try {
            synchronized(writeLock) {
                output.write(frame)
                output.flush()
            }
            true
        } catch (e: Exception) {
            Log.i(TAG, "AOA write failed: $e")
            lastError.value = "USB connection dropped. Check the cable."
            closeLink()
            false
        }
    }

    private fun startReader(opened: Link) {
        readerJob?.cancel()
        readerJob = scope.launch {
            val buffer = ByteArray(64 * 1024)
            var pending = ByteArray(0)
            try {
                while (isActive && link === opened) {
                    val n = opened.input.read(buffer)
                    if (n < 0) break
                    val chunk = buffer.copyOf(n)
                    val current = relay
                    if (current != null && !current.closed) {
                        val forwarded = runCatching {
                            current.socket.getOutputStream().write(chunk)
                            current.socket.getOutputStream().flush()
                        }.isSuccess
                        if (forwarded) continue
                        current.close()
                        relay = null
                    }
                    pending = parseAccessory(pending + chunk)
                }
            } catch (e: Exception) {
                Log.i(TAG, "AOA read ended: $e")
            } finally {
                if (link === opened) {
                    lastError.value = if (foreground) "USB connection ended. Check the cable." else null
                    closeLink()
                }
            }
        }
    }

    private fun parseAccessory(pending: ByteArray): ByteArray {
        var bytes = pending
        while (bytes.size >= 4) {
            val length = ByteBuffer.wrap(bytes, 0, 4).int
            if (length <= 0 || length > USBAccessoryWire.MAX_MESSAGE_BYTES) {
                Log.i(TAG, "AOA: invalid frame length $length")
                closeLink()
                return ByteArray(0)
            }
            if (bytes.size < 4 + length) return bytes
            val body = bytes.copyOfRange(4, 4 + length)
            val rest = bytes.copyOfRange(4 + length, bytes.size)
            bytes = rest
            val message = runCatching { USBAccessoryWire.parse(body) }.getOrNull() ?: continue
            when (message) {
                is USBAccessoryMessage.Advertisement -> currentHost.value = message.advertisement
                is USBAccessoryMessage.Relay -> {
                    if (!startRelay(message.relay, rest)) return ByteArray(0)
                    return ByteArray(0)
                }
                is USBAccessoryMessage.Request -> Unit
            }
        }
        return bytes
    }

    /**
     * Splices the accessory stream to a loopback listener the app already owns:
     * the pinned TLS listener (9001) or the pairing listener (9002). The Mac
     * sits on the other end of the same bytes; TLS/pinning is unchanged.
     */
    private fun startRelay(command: USBAccessoryRelay, buffered: ByteArray): Boolean {
        if (command.port != USBAccessoryWire.TLS_RELAY_PORT && command.port != USBAccessoryWire.PAIRING_RELAY_PORT) {
            Log.i(TAG, "AOA: refusing relay to port ${command.port}")
            return false
        }
        val socket = try {
            Socket().apply {
                tcpNoDelay = true
                connect(InetSocketAddress("127.0.0.1", command.port), 2_000)
            }
        } catch (e: Exception) {
            Log.i(TAG, "AOA relay to ${command.port} failed: $e")
            lastError.value = "USB is connected, but the Mac couldn't reach the receiver."
            return false
        }
        val writer = scope.launch {
            try {
                val input = socket.getInputStream()
                val output = link?.output ?: return@launch
                val buffer = ByteArray(64 * 1024)
                while (isActive) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    synchronized(writeLock) {
                        output.write(buffer, 0, n)
                        output.flush()
                    }
                }
            } catch (e: Exception) {
                Log.i(TAG, "AOA relay write ended: $e")
            } finally {
                relay?.takeIf { it.socket === socket }?.let { relay = null }
                runCatching { socket.close() }
            }
        }
        val session = Relay(command.port, socket, writer)
        relay = session
        Log.i(TAG, "AOA relay open to 127.0.0.1:${command.port}")
        if (buffered.isNotEmpty()) {
            runCatching { socket.getOutputStream().write(buffered); socket.getOutputStream().flush() }
                .onFailure { session.close(); relay = null }
        }
        return true
    }

    private companion object { const val TAG = "ExtendPadUSB" }
}
