package app.storyarc.feature.epubreader

import android.os.Looper
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.persistence.ReaderPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * That the reader's own named colour survives a preset tap and a whole-theme reset, which
 * drop only what is *in force*.
 *
 * `reading-themes`, *Custom colour and the six presets*: "it is stored as a seventh,
 * user-named slot alongside the six presets rather than overwriting one". The slot lived
 * only inside `theme.custom`, which a preset tap drops on purpose — so the seventh card
 * vanished the moment the reader tapped any of the other six, and its own tap re-applied a
 * palette that was already gone. `EpubReaderViewModel.customPalette` is the slot now, kept
 * whether or not it is in force, and `theme.custom` is only what is on the page right now.
 *
 * iOS mirrors this suite in `CustomColourSlotTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CustomColourSlotTest {

    private val mine = ReaderPalette(name = "Mine", background = "#123456", foreground = "#FEDCBA")

    private fun reader(on: ThemePreset, themeStore: ReaderPreferences? = null): EpubReaderViewModel {
        val model = EpubReaderViewModel(
            application = RuntimeEnvironment.getApplication(),
            location = NOWHERE,
            identity = PublicationIdentity(normalizedPath = NOWHERE),
            progress = null,
            themeStore = themeStore,
        )
        model.adopt(on)
        return model
    }

    private fun settle() {
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun `tapping a preset drops what is in force, and keeps the slot`() {
        val reader = reader(on = ThemePreset.PAPER)
        reader.adoptColours(mine)

        reader.adopt(ThemePreset.CALM)

        assertEquals(
            "The slot went with the preset. `reading-themes` keeps a custom colour" +
                " \"alongside the six presets rather than overwriting one\", and a preset" +
                " that erases it is the preset overwriting it.",
            mine,
            reader.customPalette.value,
        )
        assertNull(
            "Tapping one of the six presets left the reader's own colours on the page too.",
            reader.theme.value.custom,
        )
    }

    @Test
    fun `a whole-theme reset drops what is in force, and keeps the slot`() {
        val reader = reader(on = ThemePreset.CALM)
        reader.set(ThemeAxis.LINE_SPACING, 2.4)
        reader.adoptColours(mine)

        reader.restoreTheme()

        assertEquals(
            "The reset discarded the reader's own palette.",
            mine,
            reader.customPalette.value,
        )
        assertNull(
            "The reset kept the reader's own colour in force, so the background did not" +
                " return to Calm's own value along with every other axis.",
            reader.theme.value.custom,
        )
    }

    @Test
    fun `tapping the seventh card puts the slot back in force`() {
        val reader = reader(on = ThemePreset.PAPER)
        reader.adoptColours(mine)
        reader.adopt(ThemePreset.CALM)
        assertNull("setup: the preset tap should have dropped it", reader.theme.value.custom)

        reader.adoptColours(requireNotNull(reader.customPalette.value))

        assertEquals(
            "The card's own tap did not put the slot's palette back on the page.",
            mine,
            reader.theme.value.custom,
        )
    }

    @Test
    fun `the slot is written to the shelf, and read back by the next reader on it`() {
        val store = ReaderPreferences.open(RuntimeEnvironment.getApplication())
        val first = reader(on = ThemePreset.PAPER, themeStore = store)
        first.adoptColours(mine)
        first.adopt(ThemePreset.CALM)
        settle()

        val second = reader(on = ThemePreset.PAPER, themeStore = store)

        assertEquals(
            "The slot did not reach the store, or did not come back. A reader who left the" +
                " book and opened it again lost their own named colour, with no way back" +
                " to it.",
            mine,
            second.customPalette.value,
        )
    }

    private companion object {
        const val NOWHERE = "/nowhere.epub"
    }
}
