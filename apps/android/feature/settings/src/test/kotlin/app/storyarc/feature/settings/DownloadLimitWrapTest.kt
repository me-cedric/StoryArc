package app.storyarc.feature.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Every disk limit is reachable at the largest text size in the narrowest window.
 *
 * `design.md` §3 asks every screen to survive the largest accessibility text size, and §10
 * spells out what surviving means: "no clipping". The ladder is four chips, and it was a
 * plain `Row`. A `Row` does not fail by scrolling, and it places nothing past the edge
 * either — it never measures a child wider than the space still free. It fails by keeping
 * the chips it can fit and giving each of the rest whatever is left, which at
 * `font_scale 2.0` across this row's real 280 dp is 25 dp in English, 1 dp in German and
 * nothing at all in French. A limit squeezed into a column of single letters is one the
 * reader cannot read; a limit of no width is one no interaction reaches. That is why this
 * row was the harder half of the same defect `LibraryControls` and `ListOrderChips` fixed
 * by wrapping.
 *
 * Robolectric, and the first use of it in this repository. A layout claim is only
 * answerable inside a composition, and `testDebugUnitTest` has no device to compose on; the
 * sibling `androidTest` suites answer questions like this one only when somebody boots an
 * emulator, which is how this row stayed broken through the commit that fixed the other
 * two. The dependency is test-only and lives in this module alone.
 *
 * **`GraphicsMode.NATIVE` is load-bearing, not decoration.** Robolectric's legacy graphics
 * measure every string as though its glyphs were about a pixel wide, so the four chips fit
 * the row with room to spare and this test passes against the very `Row` it exists
 * to reject. It was written, run green, and only caught the defect once native text
 * measurement was switched on. A `qualifiers` window 1600 dp tall matters for the same
 * reason: below the wrapped content's own height the chips fall outside the root and report
 * unspecified bounds, which is a failure that says nothing about the row.
 *
 * The width is imposed with a `Modifier` and the text size with `LocalDensity`, so both
 * numbers are in the file rather than encoded in a device string. Both are settings a
 * reader chooses, not scaffolding the test needs.
 *
 * **The width measured is the row's, not the window's.** `SettingsScreen` puts this group
 * in a scrolling `Column` padded by [StoryArcSpace.gutter] on every side, so in the
 * narrowest window Android's compact class allows the ladder has [WINDOW] less twice that
 * gutter to lay chips out in. The fixture applies the same token as the same padding rather
 * than naming 280 dp, so it follows the screen if the gutter moves; it does not compose the
 * screen, so it will not follow a change of container.
 *
 * All four shipped locales, because the label that decides the layout is *No limit* and it
 * is a different length in each — and because guessing which language is the worst case is
 * how the sibling row's notes got their numbers wrong twice.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and the
// question here — how wide a chip is measured — has no API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class DownloadLimitWrapTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * The chips as [DownloadsGroup] draws them, in a window the size of the smallest phone
     * this app supports, at the largest text size Android offers.
     */
    private fun showLimits(): List<String> {
        var labels = emptyList<String>()
        compose.setContent {
            val context = LocalContext.current
            labels = LIMITS.map { limit ->
                limit?.let { Formatter.formatShortFileSize(context, it) }
                    ?: stringResource(R.string.downloads_limit_none)
            }
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = LARGEST_TEXT),
            ) {
                StoryArcTheme {
                    Column(
                        modifier = Modifier
                            .width(WINDOW)
                            .padding(horizontal = StoryArcSpace.gutter),
                    ) {
                        DownloadsGroup(bytesOnDisk = 0L)
                    }
                }
            }
        }
        compose.waitForIdle()
        // A blank or duplicated label would make the assertions below pass by matching the
        // wrong node, so the fixture proves it has four distinct labels before using them.
        assertTrue("labels were $labels", labels.none { it.isBlank() })
        assertTrue("labels were $labels", labels.toSet().size == LIMITS.size)
        return labels
    }

    @Test
    fun `every disk limit fits the row in English`() = assertLimitsFitTheRow()

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `every disk limit fits the row in German`() = assertLimitsFitTheRow()

    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `every disk limit fits the row in Spanish`() = assertLimitsFitTheRow()

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h1600dp")
    fun `every disk limit fits the row in French`() = assertLimitsFitTheRow()

    private fun assertLimitsFitTheRow() {
        showLimits().forEach { label ->
            val bounds = compose.onNodeWithText(label).getUnclippedBoundsInRoot()
            val width = bounds.right - bounds.left
            val height = bounds.bottom - bounds.top
            // Three ways a row that does not wrap loses a chip, and it takes whichever the
            // space left over allows. It can be measured into no width at all; it can be
            // measured and then placed off the end, which is what a scrolling row does; or
            // it can be squeezed into the sliver that remains, where the label becomes a
            // column of single letters. Every one of these labels is a few words on one
            // line, so any of them drawn taller than it is wide has been squeezed.
            assertTrue("$label was measured $width wide", width > Dp.Hairline)
            assertTrue("$label starts at ${bounds.left}", bounds.left >= StoryArcSpace.gutter)
            assertTrue(
                "$label ends at ${bounds.right}",
                bounds.right <= WINDOW - StoryArcSpace.gutter,
            )
            assertTrue("$label was drawn $width by $height", width > height)
        }
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f
    }
}
