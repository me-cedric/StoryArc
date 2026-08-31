package app.storyarc

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The Downloads shelf lays a cover out the way the library shelf does.
 *
 * It did not. `coverMinimum` held `design.md` §4's three tiers and ignored the reader's font
 * scale entirely, so at an accessibility text size the Downloads shelf kept 104 dp columns
 * while the library shelf widened to 146 — two shelves in one app, laying out differently,
 * with captions wrapping hard inside the narrow one. iOS had the identical divergence in
 * `OnDeviceShelf`, where Apple's accessibility audit reported it as five clipped labels.
 *
 * **This table is asserted three times in this repository and that is one time too many.**
 * `:feature:library`'s `CoverMinimumWidthTest` and iOS's `CoverMinimumWidthTests` assert the
 * same numbers, because the rule itself lives in three places: `:feature:library` holds
 * `coverMinimumWidth`, `coverMaximumWidth` and `BoundedAdaptive` and all three are `internal`
 * to that module, so `:app` cannot call them. Moving them to `:core:designsystem` — which
 * both modules already depend on, and where the rest of `design.md` already lives — would
 * leave one rule and one test. Until that happens, this file is what stops the copies
 * drifting silently.
 */
class CoverMinimumTest {

    @Test
    fun `the three tiers are design's own, at Material's own breakpoints`() {
        assertEquals(104.dp, coverMinimum(360, 1f))
        assertEquals(104.dp, coverMinimum(599, 1f))
        assertEquals(132.dp, coverMinimum(600, 1f))
        assertEquals(132.dp, coverMinimum(839, 1f))
        assertEquals(158.dp, coverMinimum(840, 1f))
        assertEquals(158.dp, coverMinimum(1400, 1f))
    }

    @Test
    fun `an unmeasured window gets the phone size rather than a crash`() {
        // A window measures zero before it is laid out, and the narrow answer is the one it
        // is safe to be briefly wrong with: every column fits at 104 dp.
        assertEquals(104.dp, coverMinimum(0, 1f))
    }

    @Test
    fun `an ordinary font scale leaves the documented tiers alone`() {
        // Android's Font size slider stops at 1.3 outside accessibility settings.
        listOf(0.85f, 1f, 1.15f, 1.29f).forEach { scale ->
            assertEquals(104.dp, coverMinimum(360, scale))
            assertEquals(132.dp, coverMinimum(600, scale))
            assertEquals(158.dp, coverMinimum(840, scale))
        }
    }

    @Test
    fun `every tier steps once at an accessibility font scale, and only once`() {
        // The three numbers `:feature:library` and iOS both land on. One step, not a scale
        // that follows the font: 1.3 and 2.0 get the same cover, because what a cramped
        // caption needs is one fewer column and a column is a step.
        listOf(1.3f, 1.5f, 1.8f, 2f).forEach { scale ->
            assertEquals(146.dp, coverMinimum(360, scale))
            assertEquals(185.dp, coverMinimum(600, scale))
            assertEquals(221.dp, coverMinimum(840, scale))
        }
    }
}
