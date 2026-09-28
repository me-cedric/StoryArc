package app.storyarc.feature.epubreader

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.ui.test.isSelectable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.values
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Where the six preset cards land, which is three across and two down.
 *
 * `native-experience`, *The preset grid on both platforms*: the six presets are "laid out in a
 * grid of three by two". iOS asserts its half in `ThemePresetGridTests.swift`, across every
 * text size. Android had nothing: the column count is `COLUMNS` in `ThemeSheetParts.kt` and the
 * grid that uses it is a `Column` of `Row`s in `ThemeSheet.kt`, so two columns and three rows
 * would have compiled, drawn, and passed every test in this module.
 *
 * A composition rather than a source grep, because the claim is a layout claim. Reading the
 * constant back would assert a number against itself and say nothing about what a reader is
 * shown: the same constant fed to a `Column` instead of a `Row` inverts the grid without
 * changing a digit.
 *
 * The cards are found by being selectable rather than by their names. Six mutually exclusive
 * options are a radio group — `PresetCard` says so — and that is the one property every card
 * has and nothing else on this level has, so a seventh card would be counted and a renamed
 * preset would not break this file.
 *
 * **This is not the whole requirement.** The second clause — each card previewing its own
 * background and typeface — is a pixel claim, and the frames under `docs/designs/screenshots/`
 * are its evidence. Nothing here was watched on an emulator.
 */
@OptIn(ExperimentalMaterial3Api::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// A phone's width, and a window tall enough that the grid is laid out rather than scrolled
// past: the sheet's own column scrolls, and an unmeasured card has no bounds to assert.
@Config(sdk = [34], qualifiers = "w360dp-h1600dp")
class ThemePresetGridTest {

    @get:Rule
    val compose = createComposeRule()

    private fun showPresets(preset: ThemePreset = ThemePreset.PAPER) {
        compose.setContent {
            StoryArcTheme(useDynamicColor = false) {
                ThemeSheet(
                    theme = ReadingTheme(preset),
                    values = preset.values,
                    onAdopt = {},
                    onAdoptColours = { true },
                    onCustomise = {},
                )
            }
        }
    }

    /** Every preset is a card, and no preset is left out of the grid. */
    @Test
    fun `every preset is a card of its own`() {
        showPresets()

        assertEquals(
            "the grid does not hold one card per preset",
            ThemePreset.entries.size,
            compose.onAllNodes(isSelectable()).fetchSemanticsNodes().size,
        )
    }

    /**
     * And they are laid out three across, two down.
     *
     * Rows and columns are both asserted. Six cards in two rows is also what two columns and
     * three rows is not, but a grid drawn one card per row would give six rows and one
     * column — so the row count alone would pass a layout that had lost its grid entirely if
     * the preset count ever changed.
     */
    @Test
    fun `the six presets are laid out three across and two down`() {
        showPresets()

        val cards = compose.onAllNodes(isSelectable()).fetchSemanticsNodes()
        val rows = cards.groupBy { it.boundsInRoot.top.roundToInt() }
        val columns = cards.map { it.boundsInRoot.left.roundToInt() }.toSet()

        assertEquals("the presets are not in two rows", 2, rows.size)
        assertEquals("the presets do not share three columns", 3, columns.size)
        for ((top, row) in rows) {
            assertEquals("the row at $top does not hold three cards", 3, row.size)
        }
    }

    /**
     * The two rows line up, so the grid reads as a grid.
     *
     * A row laid out independently of the one above it — each card taking the width its own
     * name needs — is still three across and two down, and is not a grid. The cards are
     * weighted for exactly this reason, and nothing asserted the weights.
     */
    @Test
    fun `the second row sits under the first`() {
        showPresets()

        val cards = compose.onAllNodes(isSelectable()).fetchSemanticsNodes()
        val byRow = cards
            .groupBy { it.boundsInRoot.top.roundToInt() }
            .toSortedMap()
            .values
            .map { row -> row.map { it.boundsInRoot.left.roundToInt() }.sorted() }

        assertEquals("the second row does not sit under the first", byRow.first(), byRow.last())

        // One pixel of slack, and no more: three weighted cards cannot share an odd number
        // of pixels evenly, so the row hands the remainder to whichever card is measured
        // first. A card sized to its own name is wider than that by a lot.
        val widths = cards.map { it.boundsInRoot.width.roundToInt() }
        assertTrue(
            "the cards are not all one width: $widths",
            widths.max() - widths.min() <= 1,
        )
    }
}
