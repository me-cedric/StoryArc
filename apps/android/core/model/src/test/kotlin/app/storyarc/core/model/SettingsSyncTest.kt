package app.storyarc.core.model

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `library-sync` task 3.5: settings and themes merge last-writer-wins per field. iOS's
 * `SettingsSyncTests` makes the same claims.
 */
class SettingsSyncTest {

    /** The reader's own change to a setting, stamped as `SettingsStore` stamps it. */
    private fun SyncDevice.setting(at: Long, edit: (AppSettings) -> AppSettings) {
        val after = edit(library.settings)
        val stamps = ChangeStamps.restamped(
            SettingsStamps.values(library.settings), library.settingsChangedAt,
            SettingsStamps.values(after), library.settingsChangedAt, at,
        )
        library = library.copy(settings = after, settingsChangedAt = stamps)
    }

    /** The reader's own change to a theme, stamped as `ReaderPreferences` stamps it. */
    private fun SyncDevice.theme(at: Long, edit: (ShelfSettings) -> ShelfSettings) {
        val themes = library.themes
        val after = themes.settingDefault(edit(themes.default(ThemeScope.REFLOWABLE)), ThemeScope.REFLOWABLE)
        val stamps = ChangeStamps.restamped(
            ThemeStamps.values(themes), library.themesChangedAt,
            ThemeStamps.values(after), library.themesChangedAt, at, ThemeStamps::default,
        )
        library = library.copy(themes = after, themesChangedAt = stamps)
    }

    private fun SyncDevice.reflowable() = library.themes.default(ThemeScope.REFLOWABLE)

    @Test
    fun `one device's theme and another device's font size both survive`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        val b = SyncDevice("device-b")
        a.setting(moment(1)) { it.copy(appearance = AppearanceMode.DARK) }
        a.theme(moment(2)) { it.copy(theme = ReadingTheme(preset = ThemePreset.QUIET)) }
        b.theme(moment(3)) { it.copy(values = it.values.copy(fontSize = FontSizeStep.LARGE)) }

        a.sync(place, moment(4))
        b.sync(place, moment(5))
        a.sync(place, moment(6))

        for (device in listOf(a, b)) {
            assertEquals(AppearanceMode.DARK, device.library.settings.appearance)
            assertEquals(ThemePreset.QUIET, device.reflowable().theme.preset)
            assertEquals(FontSizeStep.LARGE, device.reflowable().values.fontSize)
        }
    }

    @Test
    fun `the same field changed on both devices takes the later change`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a")
        val b = SyncDevice("device-b")
        a.setting(moment(3)) { it.copy(appearance = AppearanceMode.DARK) }
        b.setting(moment(2)) { it.copy(appearance = AppearanceMode.LIGHT) }

        // B's older change is written first, and A's later one still wins: the moment decides,
        // not the order.
        b.sync(place, moment(4))
        a.sync(place, moment(5))
        b.sync(place, moment(6))

        assertEquals(AppearanceMode.DARK, a.library.settings.appearance)
        assertEquals(AppearanceMode.DARK, b.library.settings.appearance)
        val stamp = place.document().library.settings.changed.getValue("appearance")
        assertEquals(DocumentStamp(wireMoment(moment(3)), "device-a"), stamp)
    }

    @Test
    fun `a setting the other platform cannot express keeps this device's value`() {
        val local = AppSettings(turnPagesWithVolumeButtons = true)
        // What iOS writes: no such field, and a newer moment on every field it has.
        val remote = DocumentSettings(appearance = "dark").copy(
            changed = SettingsStamps.fields.associate { it.name to DocumentStamp(wireMoment(moment(9)), "device-b") },
        )

        val merged = SettingsStamps.merging(local, emptyMap(), remote, "device-a").value

        assertEquals(true, merged.turnPagesWithVolumeButtons)
        assertEquals(AppearanceMode.DARK, merged.appearance)
    }

    @Test
    fun `a setting the document does not carry is kept`() {
        val local = AppSettings(useDynamicColor = true, lookUpMissingCovers = true)

        val merged = SettingsStamps.merging(local, emptyMap(), DocumentSettings(), "device-a").value

        assertEquals(true, merged.useDynamicColor)
        assertEquals(true, merged.lookUpMissingCovers)
    }

    @Test
    fun `a store stamps only what the reader changed, and keeps a moment a merge brought`() {
        val before = AppSettings()
        val changed = ChangeStamps.restamped(
            SettingsStamps.values(before), emptyMap(),
            SettingsStamps.values(before.copy(language = "fr")), emptyMap(), moment(7),
        )
        assertEquals(mapOf("language" to moment(7)), changed)

        val merged = ChangeStamps.restamped(
            SettingsStamps.values(before), emptyMap(),
            SettingsStamps.values(before.copy(language = "de")), mapOf("language" to moment(3)), moment(8),
        )
        assertEquals(mapOf("language" to moment(3)), merged)
    }
}
