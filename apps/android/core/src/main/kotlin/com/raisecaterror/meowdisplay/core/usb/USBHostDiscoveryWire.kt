package com.raisecaterror.meowdisplay.core.usb

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import com.raisecaterror.meowdisplay.core.remote.HostPlatform
import java.nio.ByteBuffer

/*
 * Two framed USB control channels:
 *
 * USBHostDiscoveryWire (v1) — the legacy ADB-reverse discovery socket on
 * 127.0.0.1:9005. The Mac answers Discover/Connect/Pair with an advertisement;
 * the media/pairing TLS stays on the ADB forward. Kept for devices (and the
 * current Huawei tablet) whose firmware does not complete AOA accessory mode.
 *
 * USBAccessoryWire (v2) — the same requests over the AOA bulk stream, plus a
 * `relay` message that asks the app to splice the pipe to its own loopback TLS
 * (9001) or pairing (9002) listener. Trust is unchanged; transport only.
 *
 * The media/pairing protocol versions are independent of both.
 */

enum class USBHostAction(val wireName: String) {
    Discover("discover"), Connect("connect"), Pair("pair"),
}

/**
 * [peerID] is the Mac this request is addressed to. [receiverID] is this
 * receiver's own install id: an unauthenticated hint that lets the Mac match
 * a USB device to a peer it has already pinned (for example after pairing
 * over Wi-Fi). It never grants trust — the pinned TLS handshake still decides.
 */
data class USBHostRequest(
    val version: Int,
    val action: USBHostAction,
    val peerID: String? = null,
    val receiverID: String? = null,
)

data class USBHostAdvertisement(
    val version: Int,
    val peerID: String,
    val name: String,
    val paired: Boolean,
    val platform: HostPlatform = HostPlatform.MAC,
)

/** The Mac asks an AOA app to splice the accessory stream to one of its local TLS listeners. */
data class USBAccessoryRelay(val version: Int, val port: Int)

sealed interface USBAccessoryMessage {
    data class Request(val request: USBHostRequest) : USBAccessoryMessage
    data class Advertisement(val advertisement: USBHostAdvertisement) : USBAccessoryMessage
    data class Relay(val relay: USBAccessoryRelay) : USBAccessoryMessage
}

/** v1: the ADB-reverse discovery socket (127.0.0.1:9005). Unchanged wire shape. */
object USBHostDiscoveryWire {
    const val VERSION = 1
    const val PORT = 9005
    const val MAX_MESSAGE_BYTES = 16 * 1024

    fun frame(value: USBHostRequest): ByteArray {
        val body = buildJsonObject {
            put("version", value.version)
            put("action", value.action.wireName)
            value.peerID?.let { put("peerID", it) }
            value.receiverID?.let { put("receiverID", it) }
        }.toString().toByteArray(Charsets.UTF_8)
        require(body.size in 1..MAX_MESSAGE_BYTES)
        return ByteBuffer.allocate(4 + body.size).putInt(body.size).put(body).array()
    }

    fun request(body: ByteArray): USBHostRequest {
        val root = Json.parseToJsonElement(body.toString(Charsets.UTF_8)).jsonObject
        val action = USBHostAction.entries.firstOrNull { it.wireName == root.getValue("action").jsonPrimitive.content }
            ?: throw IllegalArgumentException("Unknown USB action")
        return USBHostRequest(
            root.getValue("version").jsonPrimitive.int,
            action,
            root["peerID"]?.jsonPrimitive?.content,
            root["receiverID"]?.jsonPrimitive?.content,
        ).also { require(it.version == VERSION) }
    }

    fun advertisement(body: ByteArray): USBHostAdvertisement {
        val root = Json.parseToJsonElement(body.toString(Charsets.UTF_8)).jsonObject
        return USBHostAdvertisement(
            root.getValue("version").jsonPrimitive.int,
            root.getValue("peerID").jsonPrimitive.content,
            root.getValue("name").jsonPrimitive.content,
            root.getValue("paired").jsonPrimitive.boolean,
            HostPlatform.parse(root["platform"]?.jsonPrimitive?.content),
        ).also { require(it.version == VERSION) }
    }
}

/** v2: the AOA accessory control channel and its relay command. */
object USBAccessoryWire {
    const val VERSION = 2
    const val MAX_MESSAGE_BYTES = 16 * 1024
    const val TLS_RELAY_PORT = 9001
    const val PAIRING_RELAY_PORT = 9002

    fun frame(value: USBHostRequest): ByteArray = framed(buildJsonObject {
        put("type", "request")
        put("version", value.version)
        put("action", value.action.wireName)
        value.peerID?.let { put("peerID", it) }
        value.receiverID?.let { put("receiverID", it) }
    })

    /** Used by the Mac and by round-trip tests. */
    fun relayFrame(port: Int): ByteArray = framed(buildJsonObject {
        put("type", "relay")
        put("version", VERSION)
        put("port", port)
    })

    fun parse(body: ByteArray): USBAccessoryMessage {
        val root = Json.parseToJsonElement(body.toString(Charsets.UTF_8)).jsonObject
        require(root.getValue("version").jsonPrimitive.int == VERSION) { "Unsupported USB accessory wire version" }
        return when (root.getValue("type").jsonPrimitive.content) {
            "request" -> USBAccessoryMessage.Request(request(root))
            "advertisement" -> USBAccessoryMessage.Advertisement(advertisement(root))
            "relay" -> USBAccessoryMessage.Relay(
                USBAccessoryRelay(VERSION, root.getValue("port").jsonPrimitive.int.also {
                    require(it in 1..65535) { "Invalid relay port" }
                }),
            )
            else -> throw IllegalArgumentException("Unknown USB accessory message type")
        }
    }

    fun request(body: ByteArray): USBHostRequest =
        (parse(body) as? USBAccessoryMessage.Request ?: throw IllegalArgumentException("Not a USB request")).request

    fun advertisement(body: ByteArray): USBHostAdvertisement =
        (parse(body) as? USBAccessoryMessage.Advertisement
            ?: throw IllegalArgumentException("Not a USB advertisement")).advertisement

    private fun request(root: kotlinx.serialization.json.JsonObject): USBHostRequest {
        val action = USBHostAction.entries.firstOrNull { it.wireName == root.getValue("action").jsonPrimitive.content }
            ?: throw IllegalArgumentException("Unknown USB action")
        return USBHostRequest(
            root.getValue("version").jsonPrimitive.int,
            action,
            root["peerID"]?.jsonPrimitive?.content,
            root["receiverID"]?.jsonPrimitive?.content,
        )
    }

    private fun advertisement(root: kotlinx.serialization.json.JsonObject): USBHostAdvertisement = USBHostAdvertisement(
        root.getValue("version").jsonPrimitive.int,
        root.getValue("peerID").jsonPrimitive.content,
        root.getValue("name").jsonPrimitive.content,
        root.getValue("paired").jsonPrimitive.boolean,
        HostPlatform.parse(root["platform"]?.jsonPrimitive?.content),
    )

    private fun framed(json: kotlinx.serialization.json.JsonObject): ByteArray {
        val body = json.toString().toByteArray(Charsets.UTF_8)
        require(body.size in 1..MAX_MESSAGE_BYTES) { "USB accessory message too large" }
        return ByteBuffer.allocate(4 + body.size).putInt(body.size).put(body).array()
    }
}
