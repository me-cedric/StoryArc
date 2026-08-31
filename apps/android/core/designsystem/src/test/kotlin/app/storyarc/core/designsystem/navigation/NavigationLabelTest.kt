package app.storyarc.core.designsystem.navigation

import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.ui.unit.Density
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a navigation label measures against.
 *
 * `design.md` rule 3: every screen must survive the largest accessibility text size. The
 * navigation bar did not -- at `font_scale 2.0` "Downloads" filled its third of a 360 dp
 * window edge to edge and sat against the display boundary, and French's "Téléchargements"
 * is six characters longer again.
 *
 * Material's own answer, ported here rather than invented: a navigation label does not take
 * the system font size. `NavigationBarItemView` removes the scaling and
 * `labelFontScalingEnabled` defaults to off, which is why every stock Material app draws
 * small navigation labels at a large font scale. Material forbids the alternatives in as
 * many words -- labels "do not truncate or wrap", and do not shrink to fit -- and
 * `native-experience` forbids dropping the label, because a destination is never an
 * unlabelled icon.
 */
class NavigationLabelTest {

    private val screen = 2.75f

    @Test
    fun `the largest accessibility text size does not reach a pinned label`() {
        val reader = Density(density = screen, fontScale = 2f)

        assertEquals(1f, navigationLabelDensity(reader, isPinned = true).fontScale, 0f)
    }

    @Test
    fun `a reader who asked for smaller text does not get a smaller pinned label either`() {
        // One rule, in both directions. Material removes the scaling rather than bounding
        // it, and a bar whose labels shrank but never grew would be a rule with a side.
        val reader = Density(density = screen, fontScale = 0.85f)

        assertEquals(1f, navigationLabelDensity(reader, isPinned = true).fontScale, 0f)
    }

    @Test
    fun `the display's own density is untouched`() {
        // Only text is pinned. An icon, an indicator and the bar's own height are `dp` and
        // must keep measuring against the screen they are drawn on.
        val reader = Density(density = screen, fontScale = 2f)

        assertEquals(screen, navigationLabelDensity(reader, isPinned = true).density, 0f)
    }

    @Test
    fun `a reader already at the default is handed back what they came with`() {
        val reader = Density(density = screen, fontScale = 1f)

        assertSame(reader, navigationLabelDensity(reader, isPinned = true))
    }

    @Test
    fun `where the label has room, the reader's own text size survives`() {
        val reader = Density(density = screen, fontScale = 2f)

        assertSame(reader, navigationLabelDensity(reader, isPinned = false))
    }

    /**
     * The boundary the rule stops at, and the reason it stops there.
     *
     * The bar and the collapsed rail split a fixed, narrow measure between a fixed number of
     * destinations. The expanded rail does not, and it is the only control that draws the
     * secondary entries at all -- so pinning there would take a reader's text size away with
     * no clipping to prevent.
     */
    @Test
    fun `only the controls that ration their width hold the label to its design size`() {
        assertFalse(NavigationSuiteType.WideNavigationRailExpanded.pinsLabelFontScale)

        listOf(
            NavigationSuiteType.ShortNavigationBarCompact,
            NavigationSuiteType.ShortNavigationBarMedium,
            NavigationSuiteType.WideNavigationRailCollapsed,
        ).forEach { type ->
            assertTrue(type.toString(), type.pinsLabelFontScale)
        }
    }
}
