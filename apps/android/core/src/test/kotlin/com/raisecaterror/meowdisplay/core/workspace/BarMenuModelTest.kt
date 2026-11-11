package com.raisecaterror.meowdisplay.core.workspace

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The streamed display's menu bar on the receiver (PROTOCOL.md 6.18). */
class BarMenuModelTest {
    private val sent = mutableListOf<JsonObject>()
    private fun reply(json: String) = BarMenuReply.parse(Json.parseToJsonElement(json).jsonObject)
    private fun JsonObject.ints(k: String) = this[k]!!.jsonArray.map { it.jsonPrimitive.int }

    @Test
    fun aTapAsksForThatTitleAndPressesWithEveryTitleOnTheWay() {
        var native: Pair<Double, Double>? = null
        val m = BarMenuModel(send = { sent += it; true }, onNative = { x, y -> native = x to y })
        m.setAvailable(true, 0.04)
        assertEquals(0.04, m.ui.value.heightFraction, 0.0001)

        m.request(0.25, 0.02)
        assertEquals("barMenuRequest", sent.last()["type"]!!.jsonPrimitive.content)
        assertEquals(0.25, sent.last()["x"]!!.jsonPrimitive.double, 0.0001)
        assertEquals(emptyList<Int>(), sent.last().ints("path"))

        m.apply(reply("""{"type":"barMenu","ok":true,"path":[3],"app":"Finder","title":"编辑","height":0.05,
            "req":${sent.last()["req"]!!.jsonPrimitive.int},
            "items":[{"i":0,"t":"Undo","key":"⌘Z"},{"i":1,"t":"Open Recent","sub":true}]}"""))
        var level = m.ui.value.open.single()
        assertEquals("编辑", level.title)
        assertEquals(2, level.items.size)
        assertEquals(0.05, m.ui.value.heightFraction, 0.0001)
        assertNull("nothing native happened", native)

        m.openSubmenu(level.items[1])
        assertEquals(listOf(3, 1), sent.last().ints("path"))
        m.apply(reply("""{"type":"barMenu","ok":true,"path":[3,1],
            "req":${sent.last()["req"]!!.jsonPrimitive.int},"items":[{"i":0,"t":"notes.md"}]}"""))
        level = m.ui.value.open.last()
        assertEquals("Open Recent", level.title)
        assertEquals(2, m.ui.value.open.size)

        m.press(level.items[0])
        assertEquals("barMenuPress", sent.last()["type"]!!.jsonPrimitive.content)
        assertEquals(listOf(3, 1, 0), sent.last().ints("path"))
        assertEquals(listOf("编辑", "Open Recent", "notes.md"),
            sent.last()["titles"]!!.jsonArray.map { it.jsonPrimitive.content })
        assertTrue("the drop-down closes", m.ui.value.open.isEmpty())
    }

    @Test
    fun aNativeReplyPlaysTheOriginalTouchAndDrawsNothing() {
        var native: Pair<Double, Double>? = null
        val m = BarMenuModel(send = { sent += it; true }, onNative = { x, y -> native = x to y })
        m.setAvailable(true, null)
        m.request(0.5, 0.02)
        m.apply(reply("""{"type":"barMenu","ok":true,"native":true,"req":${sent.last()["req"]!!.jsonPrimitive.int}}"""))
        assertTrue(m.ui.value.open.isEmpty())
        assertEquals(0.5 to 0.02, native)
    }
}
