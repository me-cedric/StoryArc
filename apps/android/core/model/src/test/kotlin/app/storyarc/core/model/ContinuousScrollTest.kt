package app.storyarc.core.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where a continuous scroll draws a line between one page and the next.
 *
 * `comic-reader`, *Continuous scroll*:
 *
 * > **THEN** pages are stitched with no gap by default, with an option to show a separator
 *
 * One sentence carrying three rules, and this class asserts all three: a publication nobody
 * has told opens stitched, a reader who asks for the separator gets it, and it is drawn
 * *between* pages — never above the first one, where a band is a margin rather than a seam.
 *
 * The rule used to be a condition inside each platform's scroll container, where no test
 * could reach it. It is `ShelfSettings.showsSeparator` now, and both the container and this
 * class call it. `ContinuousScrollTests` is the iOS half.
 */
class ContinuousScrollTest {

    @Test
    fun `a publication nobody has told is stitched with no gap`() {
        val settings = ShelfSettings()
        assertFalse(settings.showsSeparator(aboveIndex = 1))
        assertFalse(settings.showsSeparator(aboveIndex = 42))
    }

    @Test
    fun `a reader who asks for the separator gets one between every pair of pages`() {
        val settings = ShelfSettings(showsPageSeparator = true)
        assertTrue(settings.showsSeparator(aboveIndex = 1))
        assertTrue(settings.showsSeparator(aboveIndex = 42))
    }

    /**
     * A band above page one is a margin, not a separator — there is nothing above it to
     * separate it from.
     */
    @Test
    fun `the first page is never given a separator, however the setting stands`() {
        assertFalse(ShelfSettings(showsPageSeparator = true).showsSeparator(aboveIndex = 0))
        assertFalse(ShelfSettings().showsSeparator(aboveIndex = 0))
    }
}
