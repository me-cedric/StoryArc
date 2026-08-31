package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Home's continue-reading run follows the reader's text size, like every other cover on the
 * screen below it.
 *
 * It did not. `coverMinimumWidth` took the font scale as an optional argument and this one
 * caller omitted it, so at an accessibility text size the library grid widened 104 → 146 dp
 * and Home's shelf stayed at the ordinary width — two runs of covers on two surfaces of one
 * app, one of them reflowed and the other not, which is the exact defect the shared rule was
 * extracted to remove. The argument has no default any more; this asserts the arithmetic that
 * change is for.
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
}
