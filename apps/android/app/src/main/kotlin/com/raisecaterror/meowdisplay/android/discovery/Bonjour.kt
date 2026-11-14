package com.raisecaterror.meowdisplay.android.discovery

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.raisecaterror.meowdisplay.core.remote.MacAdvertisement
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.suspendCancellableCoroutine
import java.net.InetAddress
import java.util.concurrent.Executors
import kotlin.coroutines.resume

/** DNS-SD service types and TXT records (PROTOCOL.md 2.1 and 2.2a). */
object ServiceTypes {
    const val MEDIA = "_opensidecar._tcp"
    const val PAIRING = "_opendisplay-pair._tcp"
    const val MAC_PAIRING = "_opendisplay-mac-pair._tcp"

    const val MEDIA_PORT = 9001
    const val PAIRING_PORT = 9002

    /** The media advertisement (2.1): `id` must equal hello's `id`. Never carries trust. */
    fun mediaTxt(installID: String, protocolVersion: Int) = mapOf("id" to installID, "pv" to protocolVersion.toString())

    /** The pairing advertisement: discovery metadata only, never a secret. */
    fun pairingTxt(installID: String, protocolVersion: Int, pairingVersion: Int) =
        mapOf("id" to installID, "pv" to protocolVersion.toString(), "pp" to pairingVersion.toString())
}

/** A Mac Bonjour shows nearby; [advert] is its TXT once resolved (null until then). */
data class NearbyMac(val serviceName: String, val advert: MacAdvertisement? = null)

data class ResolvedMac(val serviceName: String, val host: InetAddress, val port: Int, val installID: String?)

/** Publishes this receiver's services and browses for Macs through `NsdManager`. */
class Bonjour(context: Context) {
    private val appContext = context.applicationContext
    private val nsd = appContext.getSystemService(NsdManager::class.java)
    private val wifi = appContext.getSystemService(WifiManager::class.java)
    private val connectivity = appContext.getSystemService(ConnectivityManager::class.java)
    private val registrations = mutableMapOf<String, NsdManager.RegistrationListener>()
    private val found = MutableStateFlow<List<NearbyMac>>(emptyList())
    private val callbackExecutor = Executors.newSingleThreadExecutor()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val discoveryLock = Any()

    /**
     * Discovery is foreground-only, but it still has to survive the tablet being idle for hours,
     * Wi-Fi reconnecting after a long outage, and NsdManager silently stalling. [wantBrowsing] is
     * the intent (set while the app is in front), independent of whether a listener is registered
     * right now; [browse] is only the current registration, and its callbacks are checked against
     * the exact listener instance so a late failure from a stopped one cannot clobber the new one.
     */
    @Volatile private var wantBrowsing = false
    @Volatile private var browse: NsdManager.DiscoveryListener? = null
    private var discoveryGeneration = 0
    private var retryJob: Job? = null
    private var restartJob: Job? = null
    private var watchdogJob: Job? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var retryDelayMs = RETRY_INITIAL_MS
    private var browsingSinceMs = 0L

    /** Before Android 14 NsdManager resolves one service at a time: every resolve takes this. */
    private val resolveLock = Mutex()

    /** Android 14+: one live TXT watcher per nearby Mac (switched out/in arrives as an update). */
    private val txtWatchers = mutableMapOf<String, NsdManager.ServiceInfoCallback>()

    /** Before Android 14: TXT is re-read every [TXT_REFRESH_MS] while browsing. */
    private var txtRefresh: Job? = null

    val nearbyMacs: StateFlow<List<NearbyMac>> = found.asStateFlow()

    fun advertise(type: String, name: String, port: Int, txt: Map<String, String>) {
        withdraw(type)
        val info = NsdServiceInfo().apply {
            serviceName = name
            serviceType = type
            setPort(port)
            for ((key, value) in txt) setAttribute(key, value)
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {}
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(info: NsdServiceInfo) {}
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {}
        }
        registrations[type] = listener
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun withdraw(type: String) {
        registrations.remove(type)?.let { runCatching { nsd.unregisterService(it) } }
    }

    fun browseMacs() {
        wantBrowsing = true
        browsingSinceMs = SystemClock.elapsedRealtime()
        acquireMulticastLock()
        registerNetworkCallback()
        startDiscovery()
        startWatchdog()
    }

    /**
     * The home's Refresh: drop the current browse and register a new one at once. Useful when a
     * tablet has been idle for a long time and NsdManager no longer delivers results.
     */
    fun refreshBrowsing() {
        if (!wantBrowsing) {
            browseMacs()
            return
        }
        acquireMulticastLock()
        registerNetworkCallback()
        startWatchdog()
        restartDiscovery(delayMs = 0)
    }

    fun stopBrowsing() {
        wantBrowsing = false
        retryJob?.cancel()
        retryJob = null
        restartJob?.cancel()
        restartJob = null
        watchdogJob?.cancel()
        watchdogJob = null
        val old = synchronized(discoveryLock) {
            val current = browse
            browse = null
            discoveryGeneration++
            current
        }
        old?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        txtRefresh?.cancel()
        txtRefresh = null
        synchronized(txtWatchers) { txtWatchers.keys.toList() }.forEach(::unwatchTxt)
        found.value = emptyList()
        unregisterNetworkCallback()
        releaseMulticastLock()
    }

    private fun startDiscovery() {
        if (!wantBrowsing) return
        val generation: Int
        val listener: NsdManager.DiscoveryListener
        synchronized(discoveryLock) {
            if (browse != null) return
            generation = ++discoveryGeneration
            listener = discoveryListener(generation)
            browse = listener
        }
        try {
            nsd.discoverServices(ServiceTypes.MAC_PAIRING, NsdManager.PROTOCOL_DNS_SD, listener)
            Log.i(TAG, "discovery requested generation=$generation")
        } catch (e: Exception) {
            // NsdManager rejects a second registration while the previous stop is in flight.
            // Retry rather than leaving the home searching forever.
            Log.w(TAG, "discovery request failed: ${e.javaClass.simpleName}")
            if (browse === listener) browse = null
            scheduleRetry(generation)
            return
        }
        if (Build.VERSION.SDK_INT < 34) {
            if (txtRefresh?.isActive != true) {
                txtRefresh = scope.launch {
                    while (isActive) {
                        delay(TXT_REFRESH_MS)
                        found.value.map { it.serviceName }.forEach { refreshTxt(it) }
                    }
                }
            }
        }
    }

    private fun discoveryListener(generation: Int): NsdManager.DiscoveryListener =
        object : NsdManager.DiscoveryListener {
            private fun current() = browse === this

            override fun onDiscoveryStarted(serviceType: String) {
                if (!current()) return
                retryDelayMs = RETRY_INITIAL_MS
                Log.i(TAG, "discovery started generation=$generation")
            }

            override fun onDiscoveryStopped(serviceType: String) {
                if (current()) {
                    browse = null
                    Log.i(TAG, "discovery stopped generation=$generation")
                    // A stop we did not ask for (NsdManager or the system dropped it) must not
                    // leave the home searching with no browse: register again.
                    scheduleRetry(generation)
                }
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                // A late callback from a listener this object no longer owns must not clear the
                // new registration (that used to leave discovery running but untracked).
                if (!current()) return
                Log.w(TAG, "discovery failed generation=$generation error=$errorCode")
                browse = null
                scheduleRetry(generation)
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "discovery stop failed generation=$generation error=$errorCode")
            }

            override fun onServiceFound(info: NsdServiceInfo) {
                if (!current()) return
                val name = info.serviceName
                found.update { macs ->
                    val known = macs.firstOrNull { it.serviceName == name }
                    (macs.filterNot { it.serviceName == name } + (known ?: NearbyMac(name))).sortedBy { it.serviceName.lowercase() }
                }
                watchTxt(name)
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                if (!current()) return
                found.update { macs -> macs.filterNot { it.serviceName == info.serviceName } }
                unwatchTxt(info.serviceName)
            }
        }

    private fun scheduleRetry(generation: Int) {
        if (!wantBrowsing || retryJob?.isActive == true) return
        val wait = retryDelayMs
        retryDelayMs = (retryDelayMs * 2).coerceAtMost(RETRY_MAX_MS)
        Log.i(TAG, "discovery retry in ${wait}ms")
        retryJob = scope.launch {
            delay(wait)
            if (!wantBrowsing || discoveryGeneration != generation) return@launch
            startDiscovery()
        }
    }

    /** Stop the current browse and register a fresh one; a stalled NsdManager only heals this way. */
    private fun restartDiscovery(delayMs: Long = RESTART_DELAY_MS) {
        if (!wantBrowsing) return
        if (restartJob?.isActive == true) return
        restartJob = scope.launch {
            if (delayMs > 0) delay(delayMs)
            val old = synchronized(discoveryLock) {
                val current = browse
                browse = null
                discoveryGeneration++
                current
            }
            old?.let { runCatching { nsd.stopServiceDiscovery(it) } }
            delay(RESTART_SETTLE_MS)
            if (wantBrowsing) startDiscovery()
        }
    }

    /**
     * A tablet that idled for hours may keep a listener that reports nothing. While the home is
     * in front and no host is visible, re-register discovery periodically; a Mac on the network
     * then shows up without the person having to restart the app or toggle Wi-Fi.
     */
    private fun startWatchdog() {
        if (watchdogJob?.isActive == true) return
        watchdogJob = scope.launch {
            while (isActive && wantBrowsing) {
                delay(WATCHDOG_MS)
                if (wantBrowsing && found.value.isEmpty()) {
                    Log.i(TAG, "no hosts for ${WATCHDOG_MS}ms; restarting discovery")
                    restartDiscovery()
                }
            }
        }
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val manager = wifi ?: return
        runCatching {
            manager.createMulticastLock(MULTICAST_LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
        }.onSuccess { multicastLock = it }
            .onFailure { Log.w(TAG, "multicast lock unavailable: ${it.javaClass.simpleName}") }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { runCatching { if (it.isHeld) it.release() } }
        multicastLock = null
    }

    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val manager = connectivity ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            // A Wi-Fi reconnect after a long outage changes the interface discovery runs on.
            override fun onAvailable(network: Network) { refreshAfterNetworkChange() }
            override fun onLost(network: Network) { refreshAfterNetworkChange() }
        }
        runCatching { manager.registerDefaultNetworkCallback(callback) }
            .onSuccess { networkCallback = callback }
            .onFailure { Log.w(TAG, "network callback unavailable: ${it.javaClass.simpleName}") }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        networkCallback = null
        runCatching { connectivity?.unregisterNetworkCallback(callback) }
    }

    private fun refreshAfterNetworkChange() {
        if (!wantBrowsing) return
        // registerDefaultNetworkCallback reports the current network immediately; do not let that
        // tear down the browse that was just registered.
        if (SystemClock.elapsedRealtime() - browsingSinceMs < NETWORK_REFRESH_GRACE_MS) return
        Log.i(TAG, "network changed; restarting discovery")
        found.value = emptyList()
        restartDiscovery(delayMs = RESTART_DELAY_MS)
    }

    private fun applyTxt(serviceName: String, info: NsdServiceInfo) {
        val txt = info.attributes.mapValues { (_, value) -> value?.toString(Charsets.UTF_8) }
        val advert = MacAdvertisement.parse(txt)
        found.update { macs -> macs.map { if (it.serviceName == serviceName) it.copy(advert = advert) else it } }
    }

    private fun watchTxt(serviceName: String) {
        if (Build.VERSION.SDK_INT < 34) {
            scope.launch { refreshTxt(serviceName) }
            return
        }
        synchronized(txtWatchers) {
            if (serviceName in txtWatchers) return
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                    synchronized(txtWatchers) { txtWatchers.remove(serviceName) }
                }
                override fun onServiceUpdated(info: NsdServiceInfo) = applyTxt(serviceName, info)
                override fun onServiceLost() {}
                override fun onServiceInfoCallbackUnregistered() {}
            }
            txtWatchers[serviceName] = callback
            val query = NsdServiceInfo().apply { this.serviceName = serviceName; serviceType = ServiceTypes.MAC_PAIRING }
            runCatching { nsd.registerServiceInfoCallback(query, callbackExecutor, callback) }
                .onFailure { txtWatchers.remove(serviceName) }
        }
    }

    private fun unwatchTxt(serviceName: String) {
        if (Build.VERSION.SDK_INT < 34) return
        val callback = synchronized(txtWatchers) { txtWatchers.remove(serviceName) } ?: return
        runCatching { nsd.unregisterServiceInfoCallback(callback) }
    }

    /** Before Android 14: one resolve, in turn with every other. */
    private suspend fun refreshTxt(serviceName: String) {
        if (found.value.none { it.serviceName == serviceName }) return
        resolveInfo(serviceName)?.let { applyTxt(serviceName, it) }
    }

    @Suppress("DEPRECATION")
    private suspend fun resolveInfo(serviceName: String): NsdServiceInfo? = resolveLock.withLock {
        withTimeoutOrNull(RESOLVE_TIMEOUT_MS) {
            suspendCancellableCoroutine { continuation ->
                val query = NsdServiceInfo().apply { this.serviceName = serviceName; serviceType = ServiceTypes.MAC_PAIRING }
                nsd.resolveService(query, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) { if (continuation.isActive) continuation.resume(null) }
                    override fun onServiceResolved(info: NsdServiceInfo) { if (continuation.isActive) continuation.resume(info) }
                })
            }
        }
    }

    /** Resolves one Mac's address and TXT `id` when the user asks to pair with it. */
    suspend fun resolve(mac: NearbyMac): ResolvedMac? = suspendCancellableCoroutine { continuation ->
        val query = NsdServiceInfo().apply {
            serviceName = mac.serviceName
            serviceType = ServiceTypes.MAC_PAIRING
        }
        fun finish(info: NsdServiceInfo?) {
            val host = info?.let { if (Build.VERSION.SDK_INT >= 34) it.hostAddresses.firstOrNull() else @Suppress("DEPRECATION") it.host }
            val resolved = if (info != null && host != null) {
                ResolvedMac(mac.serviceName, host, info.port, info.attributes["id"]?.toString(Charsets.UTF_8))
            } else null
            if (continuation.isActive) continuation.resume(resolved)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val callback = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) = finish(null)
                override fun onServiceUpdated(info: NsdServiceInfo) {
                    finish(info)
                    runCatching { nsd.unregisterServiceInfoCallback(this) }
                }
                override fun onServiceLost() = finish(null)
                override fun onServiceInfoCallbackUnregistered() {}
            }
            nsd.registerServiceInfoCallback(query, callbackExecutor, callback)
            continuation.invokeOnCancellation { runCatching { nsd.unregisterServiceInfoCallback(callback) } }
        } else {
            // In turn with the TXT refreshes: NsdManager rejects a second resolve in flight.
            val job = scope.launch { finish(resolveInfo(mac.serviceName)) }
            continuation.invokeOnCancellation { job.cancel() }
        }
    }

    private companion object {
        const val TAG = "MeowDiscovery"
        const val TXT_REFRESH_MS = 30_000L
        const val RESOLVE_TIMEOUT_MS = 10_000L
        const val MULTICAST_LOCK_TAG = "extendpad-discovery"
        const val RETRY_INITIAL_MS = 2_000L
        const val RETRY_MAX_MS = 30_000L
        const val RESTART_DELAY_MS = 400L
        const val RESTART_SETTLE_MS = 600L
        const val WATCHDOG_MS = 20_000L
        const val NETWORK_REFRESH_GRACE_MS = 2_000L
    }
}
