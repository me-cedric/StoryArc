package app.storyarc.core.persistence

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/**
 * `settings-and-about` requires appearance to persist, a reset to leave sources,
 * downloads and reading progress alone, and — the one worth a test rather than a glance
 * — the reading theme to survive a change of app appearance.
 *
 * Instrumented because `SharedPreferences` needs a real `Context`, and what is being
 * asserted is that values round-trip through storage and that two stores stay out of
 * each other's way.
 *
 * iOS's `SettingsStoreTests` asserts the same table.
 */
@RunWith(AndroidJUnit4::class)
class SettingsStoreTest {

    /** Both stores over one private preferences file, so a reset can be watched. */
    private class Stores(val settings: SettingsStore, val reader: ReaderPreferences)

    private fun fresh(): Stores {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        // A private file per test, so one test's leftovers cannot pass another.
        val file = context.getSharedPreferences("test-${UUID.randomUUID()}", Context.MODE_PRIVATE)
        return Stores(SettingsStore(file), ReaderPreferences(file))
    }

    @Test
    fun every_setting_comes_back_on_the_next_launch() {
        val stores = fresh()
        stores.settings.save(
            AppSettings(
                appearance = AppearanceMode.OLED_DARK,
                language = "fr",
                turnPagesWithVolumeButtons = true,
                linkReadingThemeToAppearance = true,
            ),
        )

        val restored = stores.settings.settings()
        assertEquals(AppearanceMode.OLED_DARK, restored.appearance)
        assertEquals("fr", restored.language)
        assertTrue(restored.turnPagesWithVolumeButtons)
        assertTrue(restored.linkReadingThemeToAppearance)
    }

    @Test
    fun an_untouched_store_is_the_documented_defaults() {
        val settings = fresh().settings.settings()
        assertEquals(AppearanceMode.SYSTEM, settings.appearance)
        // Null rather than the current system language: the difference between "has not
        // chosen" and "chose whatever the system happened to be set to".
        assertNull(settings.language)
        assertFalse(settings.turnPagesWithVolumeButtons)
        // Off, because `settings-and-about` says the two are separate and this is the
        // opt-in it then allows.
        assertFalse(settings.linkReadingThemeToAppearance)
    }

    @Test
    fun changing_appearance_leaves_the_reading_theme_alone() {
        val stores = fresh()
        // `settings-and-about`: "the reading theme is not overridden, because a dark app
        // chrome with a paper-white page is a legitimate preference". The two live in
        // separate stores, which is exactly why this is a test — nothing about the code
        // stops a future hand writing one from the other.
        val paper = ShelfSettings(ReadingTheme(ThemePreset.PAPER))
        stores.reader.save(ShelfMemory().remembering(paper, ThemeScope.REFLOWABLE, "Bone"))

        stores.settings.save(AppSettings(appearance = AppearanceMode.OLED_DARK))

        val theme = stores.reader.themes().theme(ThemeScope.REFLOWABLE, "Bone")
        assertEquals(ThemePreset.PAPER, theme.theme.preset)
    }

    @Test
    fun a_reset_returns_the_settings_and_nothing_else() {
        val stores = fresh()
        // The claim the reset dialogue has to make: sources, downloads and reading
        // progress are not affected. It is true because `AppSettings` holds none of them,
        // and this asserts the neighbouring store survives.
        val calm = ShelfSettings(ReadingTheme(ThemePreset.CALM))
        stores.reader.save(ShelfMemory().remembering(calm, ThemeScope.FIXED_LAYOUT, "Bone"))
        stores.reader.save(PageFit.WIDTH)
        stores.settings.save(
            AppSettings(appearance = AppearanceMode.LIGHT, turnPagesWithVolumeButtons = true),
        )

        stores.settings.reset()

        assertEquals(AppSettings.Defaults, stores.settings.settings())
        assertEquals(
            ThemePreset.CALM,
            stores.reader.themes().theme(ThemeScope.FIXED_LAYOUT, "Bone").theme.preset,
        )
        assertEquals(PageFit.WIDTH, stores.reader.pageFit())
    }
}
