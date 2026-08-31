package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
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
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibrarySort
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Both of a reading list's order chips are on screen at the largest text size, in every
 * language this app ships.
 *
 * The pair is at its longest exactly when it exists at all: the second chip appears only
 * while a sort is overriding the list, and the first chip then names that sort.
 * [LibrarySort.FILE_SIZE] is the longest of those names in all four locales — measured, not
 * assumed — and the second chip is the way back, the one a reader who wants out is reaching
 * for.
 *
 * This row scrolled sideways before, which is worse than it sounds: a `horizontalScroll`
 * measures its children with no width limit at all, so the second chip is drawn in full and
 * placed past the edge of the window with nothing on screen saying the row moves. Wrapping
 * is what replaced it, and this is the assertion that was missing when it did.
 *
 * **The width here is the row's, not the window's.** `ShelfDetailScreen` draws these chips
 * inside a `LazyColumn` whose `contentPadding` is [StoryArcSpace.gutter] on every side, so
 * in the narrowest window Android's compact class allows the row has [WINDOW] less twice
 * that gutter to lay chips out in. This fixture applies the same token as the same padding
 * rather than naming 280 dp, so it follows the screen if the gutter moves; it does not
 * compose the screen itself, so it will not follow a change of container.
 *
 * `GraphicsMode.NATIVE` is load-bearing. Robolectric's legacy graphics measure every string
 * as roughly a pixel per glyph, which makes any chip row fit any window and any test of one
 * pass against the defect it was written to reject. The tall window is scaffolding of the
 * same kind: content taller than the root reports unspecified bounds, and that is a failure
 * that says nothing about the row.
 *
 * All four locales, because no one of them is the worst case for both chips. At the row's
 * real width the longest sort name saturates it in German, Spanish and French alike, and the
 * widest way back is German's `Reihenfolge der Liste` while the widest sort name is
 * Spanish's `Tamaño en este dispositivo` — the one label that does not fit one line of even
 * the full 320 dp window. Naming a champion locale is how the notes around this row came to
 * state a worst case that was not one; measuring all four is cheaper than arguing about it.
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

    @Test
    fun `both order chips fit the row in English`() = assertChipsFitTheRow()

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h1600dp")
    fun `both order chips fit the row in German`() = assertChipsFitTheRow()

    @Test
    @Config(qualifiers = "es-rES-w320dp-h1600dp")
    fun `both order chips fit the row in Spanish`() = assertChipsFitTheRow()

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h1600dp")
    fun `both order chips fit the row in French`() = assertChipsFitTheRow()

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
                    Column(
                        modifier = Modifier
                            .width(WINDOW)
                            .padding(horizontal = StoryArcSpace.gutter),
                    ) {
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
        // proves the pair is distinct before anything is measured through it.
        assertTrue("labels were $labels", labels.none { it.isBlank() })
        assertTrue("labels were $labels", labels.toSet().size == 2)
        return labels
    }

    /**
     * Every way a row that does not wrap loses a chip, asserted rather than described.
     *
     * A row with no wrap and no scroll measures its children in order against the space
     * still free, and takes whichever failure the leftovers allow. It can measure a chip
     * into no width at all, which is what happens once a long first chip has taken the line
     * — no interaction reaches a chip of zero width. It can squeeze one into the sliver
     * that remains, where the label becomes a column of single letters: still tappable, and
     * still unreadable. A row that scrolls instead draws the chip in full and places it past
     * the right edge, reachable only by a gesture nothing on screen advertises.
     *
     * Each of the three has its own assertion here, because two of them let the third pass:
     * a squeezed chip has a real width and sits inside the row, and only its shape gives it
     * away. Every one of these labels is a few words, so a chip taller than it is wide has
     * been squeezed — even where the label has honestly taken two lines, since the row is
     * 280 dp across and two lines of chip are 76 dp tall.
     */
    private fun assertChipsFitTheRow() {
        showChips().forEach { label ->
            val bounds = compose.onNodeWithText(label).getUnclippedBoundsInRoot()
            val width = bounds.right - bounds.left
            val height = bounds.bottom - bounds.top
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

        /**
         * The sort whose name is longest, and it is longest in all four shipped locales:
         * *Size on this device*, `Größe auf diesem Gerät`, `Tamaño en este dispositivo`,
         * `Taille sur cet appareil`. Measured at `font_scale 2.0` against the other six.
         */
        val WIDEST_SORT = LibrarySort.FILE_SIZE
    }
}
