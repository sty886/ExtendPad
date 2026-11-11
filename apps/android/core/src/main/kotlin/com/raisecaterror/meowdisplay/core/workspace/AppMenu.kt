package com.raisecaterror.meowdisplay.core.workspace

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put

// Pane menu bar (PROTOCOL.md 6.13): the menus of the app the focused Window-mode pane shows,
// read from the Mac one level at a time and pressed there. Control only; the Mac never sends
// the Apple menu. Mirrors iOS Shared/AppMenu.swift.

object AppMenuWire {
    const val WELCOME_FEATURE = "menus"
    const val REQUEST = "menuRequest"
    const val MENU = "menu"
    const val PRESS = "menuPress"
    const val RESULT = "menuResult"

    fun read(tile: String, path: List<Int>, req: Int) = buildJsonObject {
        put("type", REQUEST); put("tile", tile); put("path", ints(path)); put("req", req)
    }

    fun press(tile: String, path: List<Int>, titles: List<String>, req: Int) = buildJsonObject {
        put("type", PRESS); put("tile", tile); put("path", ints(path)); put("titles", buildJsonArray { titles.forEach { add(JsonPrimitive(it)) } }); put("req", req)
    }

    private fun ints(list: List<Int>) = buildJsonArray { list.forEach { add(JsonPrimitive(it)) } }
}

data class AppMenuEntry(
    val index: Int,
    val title: String,
    val enabled: Boolean = true,
    val checked: Boolean = false,
    val separator: Boolean = false,
    val hasSubmenu: Boolean = false,
    val shortcut: String? = null,
)

data class AppMenuReply(
    val tile: String?, val path: List<Int>, val app: String, val items: List<AppMenuEntry>,
    val ok: Boolean, val error: String?, val req: Int?,
) {
    companion object {
        fun parse(obj: JsonObject): AppMenuReply {
            val path = (obj["path"] as? JsonArray).orEmpty().take(8).mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> !p.isString }?.intOrNull }
            val items = (obj["items"] as? JsonArray).orEmpty().take(160).mapNotNull { it as? JsonObject }.mapNotNull { o ->
                val i = o.i("i")?.takeIf { it in 0 until 500 } ?: return@mapNotNull null
                if (o.b("sep") == true) return@mapNotNull AppMenuEntry(i, "", separator = true)
                val t = o.s("t")?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                AppMenuEntry(i, t.take(120), o.b("on") != false, o.b("mark") == true, false, o.b("sub") == true, o.s("key")?.take(12))
            }
            return AppMenuReply(obj.s("tile")?.take(32), path, obj.s("app")?.take(80).orEmpty(), items,
                obj.b("ok") != false, obj.s("error")?.take(32), obj.i("req"))
        }
    }
}

/** One open menu (or submenu) in the drop-down. */
data class AppMenuLevel(
    val path: List<Int>, val titles: List<String>, val title: String,
    val items: List<AppMenuEntry> = emptyList(), val loading: Boolean = true, val error: String? = null,
)

data class AppMenuUi(
    /** The Mac offers pane menus (welcome feature `menus`). */
    val available: Boolean = false,
    /** The user's choice: the bar shows on the focused pane (default on). */
    val barShown: Boolean = true,
    /** The pane whose app's menus are shown (null: none, e.g. no control or a desktop pane). */
    val tile: String? = null,
    val app: String = "",
    val top: List<AppMenuEntry> = emptyList(),
    /** `control`, `accessibility`, `unavailable`, `notFound` for the menu bar itself. */
    val topError: String? = null,
    /** The drop-down: the open menu, then any submenus. Empty when closed. */
    val open: List<AppMenuLevel> = emptyList(),
    /** A press that didn't happen (the menu changed, or control went away). */
    val failed: String? = null,
)

/** The focused pane's app menus. Main thread only. */
class AppMenuModel(
    private val send: (JsonObject) -> Boolean,
    private val scheduler: RemoteFilesScheduler,
    barShown: Boolean = true,
    private val onBarShown: (Boolean) -> Unit = {},
) {
    private val state = MutableStateFlow(AppMenuUi(barShown = barShown))
    val ui: StateFlow<AppMenuUi> = state.asStateFlow()

    private var bundle: String? = null
    private var req = 0
    private var topReq: Int? = null
    private var levelReq: Int? = null
    private var cancelFailed: (() -> Unit)? = null
    /** The focused pane's app name from the window list; a top-level reply for another app is stale. */
    private var expectedApp: String? = null
    private var staleRetries = 0
    private var cancelRetry: (() -> Unit)? = null

    fun setAvailable(value: Boolean) {
        state.update { it.copy(available = value) }
        if (!value) reset()
    }

    fun setBarShown(value: Boolean) {
        state.update { it.copy(barShown = value) }
        onBarShown(value)
    }

    fun reset() {
        bundle = null; topReq = null; levelReq = null
        cancelRetry?.invoke(); cancelRetry = null
        state.update { AppMenuUi(available = it.available, barShown = it.barShown) }
    }

    /** The focused pane (and its app) changed, or control came or went. */
    fun sync(tile: String?, bundle: String?, enabled: Boolean, appName: String? = null) {
        expectedApp = appName?.takeIf { it.isNotEmpty() }
        val s = state.value
        if (!s.available || !enabled || tile == null || bundle.isNullOrEmpty()) {
            if (s.tile != null) reset()
            return
        }
        if (tile == s.tile && bundle == this.bundle) return
        this.bundle = bundle
        staleRetries = 0
        state.update { it.copy(tile = tile, app = "", top = emptyList(), topError = null, open = emptyList()) }
        val r = nextReq()
        topReq = r
        send(AppMenuWire.read(tile, emptyList(), r))
    }

    fun refresh() {
        val tile = state.value.tile ?: return
        val r = nextReq()
        topReq = r
        send(AppMenuWire.read(tile, emptyList(), r))
    }

    fun openMenu(e: AppMenuEntry) {
        if (state.value.tile == null || e.separator) return
        if (state.value.open.firstOrNull()?.path == listOf(e.index)) return close()
        state.update { it.copy(open = emptyList()) }
        push(listOf(e.index), listOf(e.title), e.title)
    }

    fun openSubmenu(e: AppMenuEntry) {
        val level = state.value.open.lastOrNull() ?: return
        if (!e.hasSubmenu || !e.enabled) return
        push(level.path + e.index, level.titles + e.title, e.title)
    }

    fun back() {
        if (state.value.open.size > 1) { levelReq = null; state.update { it.copy(open = it.open.dropLast(1)) } } else close()
    }

    fun close() { levelReq = null; state.update { it.copy(open = emptyList()) } }

    /** Presses a menu item on the Mac (the Mac brings the pane's window forward first, like a click). */
    fun press(e: AppMenuEntry) {
        val s = state.value
        val tile = s.tile ?: return
        val level = s.open.lastOrNull() ?: return
        if (!e.enabled || e.separator || e.hasSubmenu) return
        send(AppMenuWire.press(tile, level.path + e.index, level.titles + e.title, nextReq()))
        close()
    }

    private fun push(path: List<Int>, titles: List<String>, title: String) {
        val tile = state.value.tile ?: return
        state.update { it.copy(open = it.open + AppMenuLevel(path, titles, title)) }
        val r = nextReq()
        levelReq = r
        send(AppMenuWire.read(tile, path, r))
    }

    fun apply(r: AppMenuReply) {
        val s = state.value
        if (r.tile != null && r.tile != s.tile) return
        if (r.path.isEmpty()) {
            if (r.req != null && r.req != topReq) return
            if (r.ok && isStale(r.app, expectedApp) && staleRetries < 3) {
                // The Mac answered for the pane's previous tab: ask again once it has the new window.
                staleRetries += 1
                cancelRetry?.invoke()
                cancelRetry = scheduler.after(400) { refresh() }
                return
            }
            state.update { if (r.ok) it.copy(app = r.app, top = r.items, topError = null) else it.copy(top = emptyList(), topError = r.error ?: "unavailable") }
            return
        }
        if (r.req != levelReq) return
        val i = s.open.indexOfLast { it.path == r.path }
        if (i < 0) return
        state.update { st ->
            st.copy(open = st.open.mapIndexed { j, l ->
                if (j != i) l else if (r.ok) l.copy(items = r.items, loading = false, error = null) else l.copy(loading = false, error = r.error ?: "unavailable")
            })
        }
    }

    fun applyResult(ok: Boolean, error: String?) {
        if (ok) return
        state.update { it.copy(failed = error ?: "changed") }
        cancelFailed?.invoke()
        cancelFailed = scheduler.after(2_500) { state.update { it.copy(failed = null) } }
        refresh()
    }

    companion object {
        /** A reply names a different app than the pane shows (case and accents ignored). */
        fun isStale(replyApp: String, expected: String?): Boolean {
            if (expected == null || replyApp.isEmpty()) return false
            return fold(replyApp) != fold(expected)
        }

        private fun fold(s: String) = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD)
            .replace(Regex("\\p{M}+"), "").lowercase()
    }

    private fun nextReq(): Int { req = if (req >= 1_000_000_000) 1 else req + 1; return req }
}

// MARK: - The streamed display's menu bar (PROTOCOL.md 6.18)

/** In Mirror/Extend the receiver draws the menu bar's drop-downs; the Mac reads and presses them. */
object BarMenuWire {
    const val FEATURE = "barMenus"
    const val HEIGHT_FIELD = "barMenuHeight"
    const val REQUEST = "barMenuRequest"
    const val MENU = "barMenu"
    const val PRESS = "barMenuPress"
    const val RESULT = "barMenuResult"

    fun read(x: Double, y: Double, path: List<Int>, req: Int) = buildJsonObject {
        put("type", REQUEST); put("x", x); put("y", y); put("path", ints(path)); put("req", req)
    }

    fun press(path: List<Int>, titles: List<String>, req: Int) = buildJsonObject {
        put("type", PRESS); put("path", ints(path))
        put("titles", buildJsonArray { titles.forEach { add(JsonPrimitive(it)) } }); put("req", req)
    }

    private fun ints(list: List<Int>) = buildJsonArray { list.forEach { add(JsonPrimitive(it)) } }
}

data class BarMenuReply(
    val path: List<Int>, val app: String, val title: String?, val items: List<AppMenuEntry>,
    val ok: Boolean, val native: Boolean, val error: String?, val req: Int?,
    /** The menu bar as a fraction of the streamed display, when the Mac included it. */
    val height: Double? = null,
) {
    companion object {
        fun parse(obj: JsonObject): BarMenuReply {
            val path = (obj["path"] as? JsonArray).orEmpty().take(8).mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> !p.isString }?.intOrNull }
            val items = (obj["items"] as? JsonArray).orEmpty().take(160).mapNotNull { it as? JsonObject }.mapNotNull { o ->
                val i = o.i("i")?.takeIf { it in 0 until 500 } ?: return@mapNotNull null
                if (o.b("sep") == true) return@mapNotNull AppMenuEntry(i, "", separator = true)
                val t = o.s("t")?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                AppMenuEntry(i, t.take(120), o.b("on") != false, o.b("mark") == true, false, o.b("sub") == true, o.s("key")?.take(12))
            }
            val height = (obj["height"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toDoubleOrNull()
                ?.takeIf { it in 0.005..0.2 }
            return BarMenuReply(path, obj.s("app")?.take(80).orEmpty(), obj.s("title")?.take(120), items,
                obj.b("ok") != false, obj.b("native") == true, obj.s("error")?.take(32), obj.i("req"), height)
        }
    }
}

data class BarMenuUi(
    /** The Mac offers receiver-drawn menu bar menus (`welcome` feature `barMenus`). */
    val available: Boolean = false,
    /** The menu bar as a fraction of the streamed display's height (30/800 when absent). */
    val heightFraction: Double = 30.0 / 800.0,
    /** The tapped title as a fraction of the picture's width; the drop-down is anchored there. */
    val anchorX: Double = 0.0,
    val app: String = "",
    /** The open menu, then any submenus. Empty while closed. */
    val open: List<AppMenuLevel> = emptyList(),
    val failed: String? = null,
)

/** The streamed display's menu bar. Main thread only. */
class BarMenuModel(
    private val send: (JsonObject) -> Boolean,
    /** The Mac answered `native`: send the original touch so its AppKit menu opens. */
    private val onNative: (x: Double, y: Double) -> Unit = { _, _ -> },
) {
    private val state = MutableStateFlow(BarMenuUi())
    val ui: StateFlow<BarMenuUi> = state.asStateFlow()

    private var req = 0
    private var levelReq: Int? = null
    private var anchorX = 0.0
    private var anchorY = 0.0

    fun setAvailable(value: Boolean, height: Double?) {
        state.update {
            it.copy(
                available = value,
                heightFraction = height?.takeIf { h -> h in 0.005..0.2 } ?: it.heightFraction,
            )
        }
        if (!value) close()
    }

    /** The user tapped the menu bar at [x]/[y], both normalized inside the streamed picture. */
    fun request(x: Double, y: Double) {
        if (!state.value.available) return
        anchorX = x
        anchorY = y
        state.update { it.copy(anchorX = x, open = emptyList(), failed = null) }
        val r = nextReq()
        levelReq = r
        send(BarMenuWire.read(x, y, emptyList(), r))
    }

    fun openSubmenu(e: AppMenuEntry) {
        val level = state.value.open.lastOrNull() ?: return
        if (!e.hasSubmenu || !e.enabled) return
        val path = level.path + e.index
        state.update { it.copy(open = it.open + AppMenuLevel(path, level.titles + e.title, e.title)) }
        val r = nextReq()
        levelReq = r
        send(BarMenuWire.read(anchorX, anchorY, path, r))
    }

    fun back() {
        if (state.value.open.size > 1) { levelReq = null; state.update { it.copy(open = it.open.dropLast(1)) } } else close()
    }

    fun close() { levelReq = null; state.update { it.copy(open = emptyList(), failed = null) } }

    fun press(e: AppMenuEntry) {
        val level = state.value.open.lastOrNull() ?: return
        if (!e.enabled || e.separator || e.hasSubmenu) return
        send(BarMenuWire.press(level.path + e.index, level.titles + e.title, nextReq()))
        close()
    }

    fun apply(r: BarMenuReply) {
        if (r.req != null && r.req != levelReq) return
        if (r.native) {
            close()
            onNative(anchorX, anchorY)
            return
        }
        if (!r.ok) {
            val open = state.value.open
            state.update { st ->
                if (open.isEmpty()) st.copy(failed = r.error ?: "unavailable")
                else st.copy(open = st.open.mapIndexed { i, l ->
                    if (i == st.open.lastIndex) l.copy(loading = false, error = r.error ?: "unavailable") else l
                })
            }
            return
        }
        val title = r.title ?: r.app
        state.update { st ->
            val index = st.open.indexOfLast { it.path == r.path }
            val open = if (index >= 0) {
                // A submenu keeps the title the receiver already shows; only its items change.
                st.open.mapIndexed { i, l ->
                    if (i == index) l.copy(items = r.items, loading = false, error = null) else l
                }
            } else {
                st.open + AppMenuLevel(r.path, listOf(title), title, r.items, loading = false)
            }
            st.copy(
                app = r.app.ifEmpty { st.app },
                heightFraction = r.height ?: st.heightFraction,
                open = open,
            )
        }
    }

    fun applyResult(ok: Boolean, error: String?) {
        if (!ok) state.update { it.copy(failed = error ?: "changed") }
    }

    private fun nextReq(): Int { req = if (req >= 1_000_000_000) 1 else req + 1; return req }
}

private fun JsonObject.s(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonObject.i(k: String): Int? = (this[k] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull
private fun JsonObject.b(k: String): Boolean? = (this[k] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
