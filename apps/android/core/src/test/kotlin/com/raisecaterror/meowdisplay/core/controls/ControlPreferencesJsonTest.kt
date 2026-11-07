package com.raisecaterror.meowdisplay.core.controls

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The persisted form matches what the Swift receiver's JSONEncoder writes, and old schemas migrate the same way. */
class ControlPreferencesJsonTest {
    private class MapStore : PreferenceBlobStore {
        val values = mutableMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun write(key: String, value: String) {
            values[key] = value
        }
    }

    /** Audit O6: a newer build's settings survive running this one. */
    @Test
    fun aNewerBuildsSettingsAreReadAndItsOwnFieldsKept() {
        val newer = ReceiverControlPreferences.SCHEMA_VERSION + 3
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] =
            """{"version":$newer,"trayEnabled":false,"futureSetting":"kept"}"""
        val repository = ReceiverControlPreferencesRepository(store)
        val loaded = repository.load(ReceiverControlPreferences().also { it.trayEnabled = true })
        assertFalse("the newer build's choice, not the initial default", loaded.trayEnabled)
        loaded.trayEnabled = true
        repository.save(loaded)
        val after = store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY]!!
        assertTrue("a field this build doesn't know survives", after.contains("\"futureSetting\":\"kept\""))
        assertTrue("the newer version is kept", after.contains("\"version\":$newer"))
        assertTrue(after.contains("\"trayEnabled\":true"))
    }

    @Test
    fun settingsFromThisSchemaAreSavedAsBefore() {
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] =
            """{"version":${ReceiverControlPreferences.SCHEMA_VERSION},"futureSetting":"dropped"}"""
        val repository = ReceiverControlPreferencesRepository(store)
        repository.save(repository.load())
        assertFalse(store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY]!!.contains("futureSetting"))
    }

    @Test
    fun freshPreferencesRoundTripExactly() {
        val preferences = ReceiverControlPreferences()
        preferences.activeControlProfile = ControlProfileSlot.Profile2
        preferences.controlKeyAsCommand = true
        preferences.functionTrayProfiles = preferences.functionTrayProfiles.map { profile ->
            profile.copy().also { it.setDisplay("undo", ShortcutButtonDisplay.Emoji("↩️")) }
        }
        val store = MapStore()
        val repository = ReceiverControlPreferencesRepository(store)
        repository.save(preferences)
        assertEquals(preferences, repository.load())
        assertEquals(preferences, preferences.deepCopy())
    }

    @Test
    fun actionsUseSwiftSynthesizedEnumShapes() {
        val item = ShortcutItem(id = "copy", title = "Copy", displayKey = "C", usage = 6, modifiers = ModifierChord(ControlModifier.Command))
        assertEquals(
            """{"id":"copy","title":"Copy","displayKey":"C","action":{"keyboardShortcut":{"_0":{"usage":6,"modifiers":{"modifiers":["command"]}}}}}""",
            item.toJson().toString(),
        )
        val gesture = ShortcutItem("launchpad", "Launchpad", ReceiverGesture.Launchpad, "square.grid.3x3")
        assertEquals("""{"receiverGesture":{"_0":"launchpad"}}""", gesture.action.toJson().toString())
        assertEquals("""{"keys":{}}""", ShortcutButtonDisplay.Keys.toJson().toString())
        val decoded = ShortcutItem.fromJson(parseJson("""{"id":"x","title":"X","displayKey":"X","action":{"sequence":{"_0":[{"action":{"receiverGesture":{"_0":"spotlight"}},"delayMs":200}]}},"display":{"text":{"_0":"Hi"}}}"""))
        assertEquals(ControlAction.Sequence(listOf(ControlActionStep(ControlAction.ReceiverGestureAction("spotlight"), 200))), decoded?.action)
        assertEquals(ShortcutButtonFace.Text("Hi"), decoded?.face)
    }

    @Test
    fun schemaOneGainsTabAndSchemaTwoCornerBecomesASide() {
        val store = MapStore()
        val profile = ControlProfile.canonical().copy(trayItems = ControlProfile.canonical().trayItems.filter { it.item != ControlTrayItem.Tab && it.item != ControlTrayItem.Dock })
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] =
            """{"version":1,"preferredLandscapeCorner":"bottomLeading","profiles":[${profile.toJson()}]}"""
        val loaded = ReceiverControlPreferencesRepository(store).load()
        assertEquals(ReceiverControlPreferences.SCHEMA_VERSION, loaded.version)
        assertEquals(LandscapeTraySide.Leading, loaded.preferredLandscapeSide)
        val items = loaded.profiles.single().trayItems.map { it.item }
        // Tab (schema 2) and then Dock (schema 8) each land immediately before Keyboard.
        assertEquals(items.indexOf(ControlTrayItem.Keyboard) - 2, items.indexOf(ControlTrayItem.Tab))
        assertEquals(items.indexOf(ControlTrayItem.Keyboard) - 1, items.indexOf(ControlTrayItem.Dock))
        assertTrue(loaded.profiles.single().trayItems.first { it.item == ControlTrayItem.Dock }.isVisible)
        // A save older than the opposite-side default keeps the same side.
        assertEquals(FunctionTrayPosition.SameSide, loaded.functionTrayPosition)
        assertEquals(ControlEdge.Trailing, loaded.padFunctionEdge)
    }

    @Test
    fun schemaSixteenMigrationAndNewerSchemasAreRead() {
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] =
            """{"version":15,"smartTouchEnabled":false,"autoHideEnabled":false,"pinchTarget":"app","rotateTarget":"viewport","padShowControlHints":true}"""
        val loaded = ReceiverControlPreferencesRepository(store).load()
        assertFalse("schema 22 disables Smart Touch after the older migrations", loaded.smartTouchEnabled)
        assertTrue(loaded.autoHideEnabled)
        assertEquals(ReceiverGestureTarget.Viewport, loaded.pinchTarget)
        assertEquals(ReceiverGestureTarget.Disabled, loaded.rotateTarget)
        assertFalse(loaded.padShowControlHints)

        val initial = ReceiverControlPreferences(trayEnabled = false)
        // A newer schema is read for what this build knows (audit O6), not reset to [initial].
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] = """{"version":99}"""
        val newer = ReceiverControlPreferencesRepository(store).load(initial)
        assertEquals(99, newer.version)
        assertFalse("absent keys take this build's defaults", newer.trayEnabled)
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] = """{"trayEnabled":"yes"}"""
        assertEquals(initial, ReceiverControlPreferencesRepository(store).load(initial))
        assertNull(ReceiverControlPreferences.decode(parseJson("[]")))
    }

    @Test
    fun receiverUIUpdateAppliesOnlySuppliedFields() {
        val message = parseJson("""{"type":"receiverUI","trayEnabled":false,"trackpadSensitivity":9,"inputMode":"trackpad","bogus":1}""").obj()!!
        val update = ReceiverUIPreferenceUpdate.parse(message)!!
        val preferences = ReceiverControlPreferences()
        update.apply(preferences)
        assertFalse(preferences.trayEnabled)
        assertEquals(2.0, preferences.trackpadSensitivity, 0.0)
        assertEquals(PointerInputMode.Trackpad, preferences.inputMode)
        assertTrue(preferences.keyboardButtonEnabled)
        assertNull(ReceiverUIPreferenceUpdate.parse(parseJson("""{"type":"receiverUI"}""").obj()!!))
    }
}

/** Natural Direct Touch (schema 23) and the schema-22 clean-screen preference migration. */
class TouchStylePreferenceTest {
    private class MapStore : PreferenceBlobStore {
        val values = mutableMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun write(key: String, value: String) {
            values[key] = value
        }
    }

    @Test
    fun newInstallIsNaturalAndClean() {
        val preferences = ReceiverControlPreferences()
        assertEquals("one finger scrolls instead of dragging", DirectTouchStyle.Natural, preferences.touchStyle)
        assertEquals(PointerInputMode.Direct, preferences.inputMode)
        assertFalse(preferences.naturalTouchHintShown)
        assertFalse(preferences.trayEnabled)
        assertFalse(preferences.functionTrayEnabled)
        assertFalse(preferences.smartTouchEnabled)
        assertTrue(preferences.keyboardButtonEnabled)
        assertEquals(23, ReceiverControlPreferences.SCHEMA_VERSION)
    }

    @Test
    fun schema22HidesReplacementControlsOnceAndKeepsLaterChoices() {
        val saved = ReceiverControlPreferences(
            version = 21,
            trayEnabled = true,
            keyboardButtonEnabled = false,
            inputMode = PointerInputMode.Trackpad,
            smartTouchEnabled = true,
            touchStyle = DirectTouchStyle.Natural,
            functionTrayEnabled = true,
        )
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] = saved.toJson().toString()
        val repository = ReceiverControlPreferencesRepository(store)
        val migrated = repository.load()
        assertEquals(ReceiverControlPreferences.SCHEMA_VERSION, migrated.version)
        assertFalse(migrated.trayEnabled)
        assertFalse(migrated.functionTrayEnabled)
        assertFalse(migrated.smartTouchEnabled)
        assertTrue(migrated.keyboardButtonEnabled)
        assertEquals("schema 23 then enables Natural Touch", DirectTouchStyle.Natural, migrated.touchStyle)
        assertEquals("an explicit pointer-mode choice survives", PointerInputMode.Trackpad, migrated.inputMode)

        migrated.trayEnabled = true
        migrated.functionTrayEnabled = true
        migrated.smartTouchEnabled = true
        migrated.keyboardButtonEnabled = false
        migrated.touchStyle = DirectTouchStyle.Natural
        repository.save(migrated)
        val reloaded = repository.load()
        assertTrue("schema-22 choices are not migrated again", reloaded.trayEnabled)
        assertTrue(reloaded.functionTrayEnabled)
        assertTrue(reloaded.smartTouchEnabled)
        assertFalse(reloaded.keyboardButtonEnabled)
        assertEquals(DirectTouchStyle.Natural, reloaded.touchStyle)
    }

    /**
     * Schema 21 (owner decision 2026-10-30) made everyone Classic and phones Trackpad; schema 23
     * (2026-11-07) restores Natural Touch. The pointer-mode half of 21 still applies once.
     */
    @Test
    fun schema21StillMovesPhonesToTrackpadAndSchema23RestoresNatural() {
        val saved = ReceiverControlPreferences()
        saved.version = 20
        saved.touchStyle = DirectTouchStyle.Natural
        saved.inputMode = PointerInputMode.Direct
        saved.smartTouchEnabled = false
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] = saved.toJson().toString()
        val phone = ReceiverControlPreferencesRepository(store).load(ReceiverControlPreferences.initial(isPad = true, phone = true))
        assertEquals(DirectTouchStyle.Natural, phone.touchStyle)
        assertEquals(PointerInputMode.Trackpad, phone.inputMode)
        assertFalse("other choices are kept", phone.smartTouchEnabled)
        val tablet = ReceiverControlPreferencesRepository(store).load(ReceiverControlPreferences.initial(isPad = true, phone = false))
        assertEquals(DirectTouchStyle.Natural, tablet.touchStyle)
        assertEquals(PointerInputMode.Direct, tablet.inputMode)
        // Fresh installs: phones Trackpad, tablets Direct Touch.
        assertEquals(PointerInputMode.Trackpad, ReceiverControlPreferences.initial(isPad = true, phone = true).inputMode)
        assertEquals(PointerInputMode.Direct, ReceiverControlPreferences.initial(isPad = true, phone = false).inputMode)
        // Once migrated, a later choice of Natural sticks.
        phone.touchStyle = DirectTouchStyle.Natural
        ReceiverControlPreferencesRepository(store).save(phone)
        assertEquals(DirectTouchStyle.Natural, ReceiverControlPreferencesRepository(store).load(ReceiverControlPreferences.initial(isPad = true, phone = true)).touchStyle)
    }

    @Test
    fun blobWithoutTheFieldBecomesNaturalAndKeepsEverythingElse() {
        val old = ReceiverControlPreferences()
        old.inputMode = PointerInputMode.Trackpad
        old.smartTouchEnabled = false
        old.pinchTarget = ReceiverGestureTarget.App
        old.trayEnabled = false
        val json = kotlinx.serialization.json.JsonObject(
            old.toJson().filterKeys { it != "touchStyle" && it != "naturalTouchHintShown" } +
                ("version" to kotlinx.serialization.json.JsonPrimitive(18)),
        )
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] = json.toString()
        val loaded = ReceiverControlPreferencesRepository(store).load()
        assertEquals(DirectTouchStyle.Natural, loaded.touchStyle)
        assertFalse(loaded.naturalTouchHintShown)
        assertEquals(ReceiverControlPreferences.SCHEMA_VERSION, loaded.version)
        val expected = old.deepCopy()
        expected.version = ReceiverControlPreferences.SCHEMA_VERSION
        assertEquals(expected, loaded)
        assertEquals(PointerInputMode.Trackpad, loaded.inputMode)
    }

    @Test
    fun classicPersistsAcrossRestart() {
        val store = MapStore()
        val p = ReceiverControlPreferences()
        p.touchStyle = DirectTouchStyle.Classic
        p.naturalTouchHintShown = true
        ReceiverControlPreferencesRepository(store).save(p)
        val reloaded = ReceiverControlPreferencesRepository(store).load()
        assertEquals(DirectTouchStyle.Classic, reloaded.touchStyle)
        assertTrue(reloaded.naturalTouchHintShown)
    }
}

/** Window Switcher preference (schema 20): Stage Peek from the left edge unless Rail or the right edge was chosen; nothing else in a saved blob changes. */
class WindowSwitcherPreferenceTest {
    private class MapStore : PreferenceBlobStore {
        val values = mutableMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun write(key: String, value: String) {
            values[key] = value
        }
    }

    @Test
    fun newInstallIsStagePeekFromTheLeft() {
        assertEquals(WindowSwitcherStyle.StagePeek, ReceiverControlPreferences().windowSwitcher)
        assertEquals(StagePeekEdge.Left, ReceiverControlPreferences().stagePeekEdge)
        assertEquals("stagePeek", WindowSwitcherStyle.StagePeek.raw)
        assertEquals("rail", WindowSwitcherStyle.Rail.raw)
        assertEquals("left", StagePeekEdge.Left.raw)
        assertEquals("right", StagePeekEdge.Right.raw)
    }

    @Test
    fun blobWithoutTheKeysDecodesToStagePeekLeftAndKeepsEverythingElse() {
        val old = ReceiverControlPreferences()
        old.touchStyle = DirectTouchStyle.Classic
        old.inputMode = PointerInputMode.Trackpad
        old.trayEnabled = false
        val json = kotlinx.serialization.json.JsonObject(
            old.toJson().filterKeys { it != "windowSwitcher" && it != "stagePeekEdge" } +
                ("version" to kotlinx.serialization.json.JsonPrimitive(19)),
        )
        val store = MapStore()
        store.values[ReceiverControlPreferencesRepository.DEFAULTS_KEY] = json.toString()
        val loaded = ReceiverControlPreferencesRepository(store).load()
        assertEquals(WindowSwitcherStyle.StagePeek, loaded.windowSwitcher)
        assertEquals(StagePeekEdge.Left, loaded.stagePeekEdge)
        // Only the documented schema-23 change remains; the switcher migration touches nothing else.
        assertEquals(DirectTouchStyle.Natural, loaded.touchStyle)
        assertEquals(ReceiverControlPreferences.SCHEMA_VERSION, loaded.version)
        val expected = old.deepCopy()
        expected.version = ReceiverControlPreferences.SCHEMA_VERSION
        expected.touchStyle = DirectTouchStyle.Natural
        assertEquals(expected, loaded)
    }

    @Test
    fun explicitChoicesPersist() {
        val store = MapStore()
        val p = ReceiverControlPreferences()
        p.windowSwitcher = WindowSwitcherStyle.Rail
        p.stagePeekEdge = StagePeekEdge.Right
        ReceiverControlPreferencesRepository(store).save(p)
        val reloaded = ReceiverControlPreferencesRepository(store).load()
        assertEquals(WindowSwitcherStyle.Rail, reloaded.windowSwitcher)
        assertEquals(StagePeekEdge.Right, reloaded.stagePeekEdge)
        assertEquals(p.toJson()["windowSwitcher"]?.toString(), "\"rail\"")
        assertEquals(p.toJson()["stagePeekEdge"]?.toString(), "\"right\"")
    }
}
