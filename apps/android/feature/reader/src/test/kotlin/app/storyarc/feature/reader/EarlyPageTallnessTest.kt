package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A webtoon that opens on a short title image is still recognised as tall.
 *
 * `comic-reader` recognises a webtoon by pages "materially taller than they are wide".
 * Deciding from the first decoded page alone read a one-page title card as ordinary
 * panels and defaulted Scroll to horizontal for the whole chapter. iOS's
 * `EarlyPageTallnessTests` asserts the same table.
 */
class EarlyPageTallnessTest {

    @Test
    fun `a short first page does not decide it alone`() {
        val tallness = EarlyPageTallness()
        tallness.note(1.2, 0)
        assertEquals(1.2, tallness.tallestRatio, 0.0)

        tallness.note(3.5, 1)
        assertEquals(3.5, tallness.tallestRatio, 0.0)
    }

    @Test
    fun `the tallest of the early pages is kept, whichever order they decode in`() {
        val tallness = EarlyPageTallness()
        tallness.note(3.5, 2)
        tallness.note(1.2, 0)
        tallness.note(2.0, 1)
        assertEquals(3.5, tallness.tallestRatio, 0.0)
    }

    @Test
    fun `a page past the sample does not raise the ratio`() {
        val tallness = EarlyPageTallness()
        tallness.note(1.0, 0)
        tallness.note(9.0, EarlyPageTallness.SAMPLE_COUNT)
        assertEquals(1.0, tallness.tallestRatio, 0.0)
    }

    @Test
    fun `nothing decoded yet reads as not tall`() {
        assertEquals(0.0, EarlyPageTallness().tallestRatio, 0.0)
    }
}
