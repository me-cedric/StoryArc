package app.storyarc.core.persistence

import app.storyarc.core.model.PageFit
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.ThemeScope
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What happens to the one page fit the whole library used to share.
 *
 * `comic-reader` requires the fit to persist per series, and it did not: one key held one
 * value, so fit-to-width chosen for a manga changed how every other comic opened. Moving
 * it into [ShelfMemory] is only half the fix — the other half is that a reader who had
 * already chosen a fit should not find every comic they own back at fit-to-screen on the
 * day they update. iOS's `SettingsStoreTests` asserts the same table.
 */
class ReaderPreferencesTest {

    private val preferences = FakePreferences()
    private val store = ReaderPreferences(preferences)

    /** What a build before the fit was per series left behind. */
    private fun writeLegacyFit(fit: PageFit) {
        preferences.edit().putString("pageFit", fit.name).apply()
    }

    @Test
    fun `the one fit the library used to share becomes the fixed-layout default`() {
        writeLegacyFit(PageFit.WIDTH)

        val memory = store.themes()

        // Every shelf that has not been told otherwise inherits it, which is what
        // "global" meant.
        assertEquals(PageFit.WIDTH, memory.theme(ThemeScope.FIXED_LAYOUT, "Bone").fit)
        assertEquals(PageFit.WIDTH, memory.default(ThemeScope.FIXED_LAYOUT).fit)
    }

    @Test
    fun `the old fit is folded in once, and a later choice is not overwritten by it`() {
        writeLegacyFit(PageFit.WIDTH)
        store.themes()
        assertNull(preferences.getString("pageFit", null))

        // The reader then sets the default to something else. A migration that ran again
        // would put fit-to-width back over it on the next read.
        val chosen = store.themes().default(ThemeScope.FIXED_LAYOUT).copy(fit = PageFit.ORIGINAL)
        store.save(store.themes().settingDefault(chosen, ThemeScope.FIXED_LAYOUT))
        assertEquals(PageFit.ORIGINAL, store.themes().default(ThemeScope.FIXED_LAYOUT).fit)
    }

    @Test
    fun `a shelf that chose its own fit keeps it when the old global one is folded in`() {
        val chosen = ShelfSettings(fit = PageFit.HEIGHT)
        store.save(ShelfMemory().remembering(chosen, ThemeScope.FIXED_LAYOUT, "Bone"))
        writeLegacyFit(PageFit.WIDTH)

        val memory = store.themes()

        assertEquals(PageFit.HEIGHT, memory.theme(ThemeScope.FIXED_LAYOUT, "Bone").fit)
        assertEquals(PageFit.WIDTH, memory.theme(ThemeScope.FIXED_LAYOUT, "Blame!").fit)
    }

    @Test
    fun `a library with no stored fit is left at fit-to-screen`() {
        assertEquals(PageFit.SCREEN, store.themes().default(ThemeScope.FIXED_LAYOUT).fit)
    }

    @Test
    fun `a fit chosen for one series is not the fit every other series opens at`() {
        val memory = ShelfMemory()
            .remembering(ShelfSettings(fit = PageFit.WIDTH), ThemeScope.FIXED_LAYOUT, "Blame!")
        store.save(memory)

        val read = store.themes()
        assertEquals(PageFit.WIDTH, read.theme(ThemeScope.FIXED_LAYOUT, "Blame!").fit)
        assertEquals(PageFit.SCREEN, read.theme(ThemeScope.FIXED_LAYOUT, "Bone").fit)
    }

    @Test
    fun `a fit written by an older build without one reads as fit-to-screen`() {
        // `ignoreUnknownKeys` covers the other direction; this is the missing-field one,
        // and losing a reader's whole theme over an added field is the thing to avoid.
        preferences.edit().putString("themes", """{"shelves":{},"defaults":{}}""").apply()
        assertEquals(PageFit.SCREEN, store.themes().default(ThemeScope.FIXED_LAYOUT).fit)
    }
}
