package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.LibrarySort
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Both of a reading list's order chips are on screen at the largest text size.
 *
 * The pair is at its longest exactly when it exists at all: the second chip appears only
 * while a sort is overriding the list, and the first chip then names that sort. *Size on
 * this device* beside *The list's order* is the widest this row ever gets, and the second
 * of the two is the way back — the chip a reader who wants out is reaching for.
 *
 * This row scrolled sideways before, which is worse than it sounds: a `horizontalScroll`
 * measures its children with no width limit at all, so the second chip is drawn in full and
 * placed past the edge of a 320 dp window with nothing on screen saying the row moves.
 * Wrapping is what replaced it, and this is the assertion that was missing when it did.
 *
 * `GraphicsMode.NATIVE` is load-bearing. Robolectric's legacy graphics measure every string
 * as roughly a pixel per glyph, which makes any chip row fit any window and any test of one
 * pass against the defect it was written to reject. The 1600 dp window height is scaffolding
 * of the same kind: content taller than the root reports unspecified bounds, and that is a
 * failure that says nothing about the row.
 *
 * German as well as English, because `Größe auf diesem Gerät` is the longest label either
 * chip row in this module has to draw, and the KDoc on `ListOrderChips` records the case as
 * open. It is open no longer.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and the
// question here — how wide a chip is measured — has no API level in it.
@Config(sdk = [34], qualifiers = "w320dp-h1600dp")
class ListOrderChipsWrapTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * The chips as `ShelfDetailScreen` draws them while a sort overrides the list, in the
     * narrowest window this app supports, at the largest text size Android offers.
     */
    private fun showChips(): List<String> {
        var labels = emptyList<String>()
        val order = ListOrder(sort = WIDEST_SORT)
        compose.setContent {
            labels = listOf(
                stringResource(WIDEST_SORT.labelRes),
                stringResource(R.string.shelves_list_order),
            )
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = LARGEST_TEXT),
            ) {
                StoryArcTheme {
                    Column(modifier = Modifier.width(WINDOW)) {
                        ListOrderChips(
                            order = order,
                            onSortChange = {},
                            onDirectionChange = {},
                            onCurated = {},
                        )
                    }
                }
            }
        }
        compose.waitForIdle()
        // Two chips that read the same would let one node answer for both, so the fixture
        // proves the pair is distinct before anything is measured through it. That the two
        // labels differ is the correction this file's sibling KDoc needed as well.
        assertTrue("labels were $labels", labels.none { it.isBlank() })
        assertTrue("labels were $labels", labels.toSet().size == 2)
        return labels
    }

    @Test
    fun `both order chips are measured and placed inside the window`() {
        showChips().forEach { label ->
            val bounds = compose.onNodeWithText(label).getUnclippedBoundsInRoot()
            val width = bounds.right - bounds.left
            // A row that does not wrap loses a chip in one of two ways, depending on what it
            // does with the space it has run out of: it draws the chip in full and places it
            // past the edge, which is what a horizontally scrolling row does, or it squeezes
            // the chip into what is left, which is what a plain row does.
            assertTrue("$label was measured $width wide", width > Dp.Hairline)
            assertTrue("$label ends at ${bounds.right}", bounds.right <= WINDOW)
        }
    }

    /**
     * German, where the same two labels are longest.
     *
     * `Größe auf diesem Gerät` is a chip wider than a `LibraryControls` label ever gets, and
     * wrapping a row does nothing for a chip that does not fit on a line of its own. What
     * saves it is that a chip's label is ordinary text: it takes a second line inside the
     * chip and the chip grows taller rather than wider. That is the answer, and it is worth
     * an assertion rather than a sentence in a comment.
     */
    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `the longest German labels stay inside the window too`() {
        showChips().forEach { label ->
            val bounds = compose.onNodeWithText(label).getUnclippedBoundsInRoot()
            assertTrue(
                "$label was measured ${bounds.right - bounds.left} wide",
                bounds.right - bounds.left > Dp.Hairline,
            )
            assertTrue("$label ends at ${bounds.right}", bounds.right <= WINDOW)
        }
    }

    private companion object {
        /** The narrowest window Android's compact width class allows, and so the floor. */
        val WINDOW = 320.dp

        /** The largest font scale Android's accessibility settings offer. */
        const val LARGEST_TEXT = 2f

        /** The sort whose name is longest in both languages this app ships. */
        val WIDEST_SORT = LibrarySort.FILE_SIZE
    }
}
