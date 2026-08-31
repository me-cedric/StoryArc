package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Every cover on Home follows the reader's text size — the plain shelves and the hero both.
 *
 * Neither did. `coverMinimumWidth` took the font scale as an optional argument and
 * [homeShelfCoverWidth] omitted it, so at an accessibility text size the library grid on the
 * next destination widened 104 → 146 dp while Home's Up next, Recently added and Finished
 * runs stayed at the ordinary width. [homeHeroWidth] — the Keep reading card, which is the
 * largest thing on the surface — read the window alone and did not step at all. Two
 * hardcoded ladders on one screen, neither of them reading the setting. This asserts the
 * arithmetic both fixes are for.
 */
class HomeCoverWidthTest {

    /** `design.md` §4's three tiers, each a quarter wider because a shelf shows six covers. */
    @Test
    fun `a home cover is the grid's tier, scaled`() {
        assertEquals(130.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1f))
        assertEquals(165.dp, homeShelfCoverWidth(windowWidthDp = 600, fontScale = 1f))
        assertEquals(197.5.dp, homeShelfCoverWidth(windowWidthDp = 840, fontScale = 1f))
    }

    /**
     * And it takes the accessibility step with the grid. 146 is `coverMinimumWidth`'s stepped
     * phone tier; anything still at 130 here means the font scale never reached the ladder.
     */
    @Test
    fun `a home cover takes the accessibility step`() {
        assertEquals(182.5.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1.5f))
        assertEquals(231.25.dp, homeShelfCoverWidth(windowWidthDp = 600, fontScale = 1.5f))
        assertEquals(276.25.dp, homeShelfCoverWidth(windowWidthDp = 840, fontScale = 1.5f))
    }

    /**
     * The boundary itself: 1.3 is where Android's ordinary Font size slider stops, so it is
     * the first scale that steps. A cover the same width either side of it is a shelf that
     * reads the setting and ignores it.
     */
    @Test
    fun `the step lands on the accessibility boundary and not before`() {
        assertEquals(130.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1.29f))
        assertEquals(182.5.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1.3f))
    }

    /** The hero's own three widths, unchanged at every ordinary text size. */
    @Test
    fun `the hero keeps its three widths at an ordinary text size`() {
        assertEquals(200.dp, homeHeroWidth(windowWidthDp = 360, fontScale = 1f))
        assertEquals(240.dp, homeHeroWidth(windowWidthDp = 600, fontScale = 1f))
        assertEquals(280.dp, homeHeroWidth(windowWidthDp = 840, fontScale = 1f))
    }

    /**
     * And the hero steps too. This is the assertion the change exists for: the Keep reading
     * card is the largest thing on Home, and it was the one surface here with no accessibility
     * step at all. A 200 here at scale 1.5 means the hero is back to reading the window alone.
     */
    @Test
    fun `the hero takes the same accessibility step`() {
        assertEquals(280.dp, homeHeroWidth(windowWidthDp = 360, fontScale = 1.5f))
        assertEquals(336.dp, homeHeroWidth(windowWidthDp = 600, fontScale = 1.5f))
        assertEquals(392.dp, homeHeroWidth(windowWidthDp = 840, fontScale = 1.5f))
    }

    /** Same boundary as the shelf, because it is the same step. */
    @Test
    fun `the hero steps on the accessibility boundary and not before`() {
        assertEquals(200.dp, homeHeroWidth(windowWidthDp = 360, fontScale = 1.29f))
        assertEquals(280.dp, homeHeroWidth(windowWidthDp = 360, fontScale = 1.3f))
    }

    /**
     * The card never asks for more room than it is given.
     *
     * Both branches lay the card out inside a gutter on each side, so a 300 dp window — a
     * freeform slot, a folded inner display, a phone in a small split — has 260 dp for it.
     * The stepped phone tier is 280, and 280 in 260 is the overflow the cap exists to stop.
     */
    @Test
    fun `the hero is capped at the room the window leaves it`() {
        assertEquals(260.dp, homeHeroWidth(windowWidthDp = 300, fontScale = 1.5f))
        assertEquals(200.dp, homeHeroWidth(windowWidthDp = 300, fontScale = 1f))
    }
}
