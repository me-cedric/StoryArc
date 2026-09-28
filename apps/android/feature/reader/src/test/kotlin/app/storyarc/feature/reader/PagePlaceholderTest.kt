package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The placeholder ratio for a page that has not decoded, from whichever page nearby
 * has. iOS's `PagePlaceholderTests` asserts the same table.
 */
class PagePlaceholderTest {

    @Test
    fun `nothing decoded yet is the ordinary comic-page default`() {
        assertEquals(PagePlaceholder.DEFAULT_RATIO, PagePlaceholder.ratio(5, emptyMap()), 0f)
    }

    @Test
    fun `the one decoded page nearby is used, however far off it reads`() {
        assertEquals(0.4f, PagePlaceholder.ratio(5, mapOf(2 to 0.4f)), 0f)
    }

    @Test
    fun `the nearer of two decoded pages wins, whichever side it is on`() {
        val ratios = mapOf(0 to 0.65f, 10 to 0.2f)
        assertEquals(0.65f, PagePlaceholder.ratio(2, ratios), 0f)
        assertEquals(0.2f, PagePlaceholder.ratio(8, ratios), 0f)
    }

    @Test
    fun `exactly between two, the lower index wins - a plain, stable tie-break`() {
        assertEquals(0.65f, PagePlaceholder.ratio(5, mapOf(0 to 0.65f, 10 to 0.2f)), 0f)
    }

    @Test
    fun `a page that is itself decoded is its own nearest`() {
        assertEquals(9f, PagePlaceholder.ratio(3, mapOf(3 to 9f, 4 to 0.65f)), 0f)
    }
}
