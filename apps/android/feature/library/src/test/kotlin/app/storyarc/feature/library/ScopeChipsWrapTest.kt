package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Neither scope chip is squeezed at the largest text size, in any language this app ships.
 *
 * The pair says what the search is about to search, and `library-browsing` asks the screen to
 * **state** that — so a label broken mid-word is the requirement failing rather than a
 * cosmetic complaint.
 *
 * **Photographed before it was fixed.** These chips lived only inside the expanded search bar,
 * where nobody had looked at them at `font_scale 2.0`; the moment the at-rest page started
 * drawing them as well, an emulator capture showed *On this device* over four lines with a
 * lone "e" on the last one. A `Row` gives a child whatever width is left after its siblings
 * and lets the text wrap inside it; a wrapping row gives the chip its own line instead.
 *
 * **The assertion is a comparison, not a number.** Each chip is drawn twice in one
 * composition: once in the narrowest window this app supports, and once in a column with all
 * the room it could want. A label that needs one line and gets one is the same height in both;
 * a squeezed one is taller in the narrow column and the difference is the defect. Naming a
 * ceiling in dp instead would be a number to re-derive every time a type ramp moves.
 *
 * All four locales, because no one of them is the worst case — German's *Auf diesem Gerät* and
 * Spanish's *En este dispositivo* are both longer than the English, and measuring all four is
 * cheaper than arguing about which one to name.
 *
 * `GraphicsMode.NATIVE` is load-bearing: Robolectric's legacy graphics measure every string as
 * roughly a pixel per glyph, which makes any chip row fit any window and any test of one pass
 * against the defect it was written to reject.
 *
 * **And it must be said that this test did not catch the defect that prompted it.** Even with
 * native graphics the harness's text is narrower than the device's: at 320 dp and `font_scale
 * 2.0` it fits both chips on one line, where the emulator does not. It fails from about 200 dp
 * down, so it guards the same rule with less headroom than the real screen has. The proof that
 * the wrapping row fixed the real thing is the emulator pair in
 * `docs/designs/screenshots/{before,after}-2026-08-31d/`, not this file. Kept anyway: a future
 * label or type ramp that overflows even the harness's narrower measure should not reach a
 * device to be found.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w320dp-h2400dp")
class ScopeChipsWrapTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `neither scope chip is squeezed in English`() = assertNeitherChipIsSqueezed()

    @Test
    @Config(qualifiers = "de-rDE-w320dp-h2400dp")
    fun `neither scope chip is squeezed in German`() = assertNeitherChipIsSqueezed()

    @Test
    @Config(qualifiers = "es-rES-w320dp-h2400dp")
    fun `neither scope chip is squeezed in Spanish`() = assertNeitherChipIsSqueezed()

    @Test
    @Config(qualifiers = "fr-rFR-w320dp-h2400dp")
    fun `neither scope chip is squeezed in French`() = assertNeitherChipIsSqueezed()

    private fun assertNeitherChipIsSqueezed() {
        val labels = showChips()

        for (label in labels) {
            val drawn = compose.onAllNodesWithText(label)
            val narrow = drawn[NARROW].getUnclippedBoundsInRoot()
            val roomy = drawn[ROOMY].getUnclippedBoundsInRoot()

            assertEquals(
                "\"$label\" is $narrow in a $WINDOW window and $roomy with all the room it" +
                    " wants, so the narrow row is breaking it across lines.",
                (roomy.bottom - roomy.top).value.toDouble(),
                (narrow.bottom - narrow.top).value.toDouble(),
                TOLERANCE,
            )
            assertTrue(
                "\"$label\" ends at ${narrow.right}, past the $WINDOW the row has.",
                narrow.right <= WINDOW,
            )
        }
    }

    /**
     * The chips as the search page draws them, twice.
     *
     * The first copy is in the narrowest window Android's compact class allows, at the largest
     * text size it offers. The second is in a column far wider than any phone, which is the
     * control: whatever height a label takes there is the height it needs.
     */
    private fun showChips(): List<String> {
        var labels = emptyList<String>()
        compose.setContent {
            labels = listOf(
                stringResource(R.string.library_scope_all),
                stringResource(R.string.source_on_this_device),
            )
            CompositionLocalProvider(
                LocalDensity provides Density(density = 1f, fontScale = LARGEST_TEXT),
            ) {
                StoryArcTheme {
                    Column {
                        Column(modifier = Modifier.width(WINDOW)) {
                            ScopeChips(LibraryAvailability.EVERYTHING, onScopeChange = {})
                        }
                        Column(modifier = Modifier.width(ROOM_FOR_ANYTHING)) {
                            ScopeChips(LibraryAvailability.EVERYTHING, onScopeChange = {})
                        }
                    }
                }
            }
        }
        compose.waitForIdle()
        return labels
    }

    private companion object {
        /** The narrowest window Android's compact class allows. */
        val WINDOW: Dp = 320.dp

        /** Wider than any window, so a label there is laid out at its natural width. */
        val ROOM_FOR_ANYTHING: Dp = 1_600.dp

        /** Android's largest accessibility text size. */
        const val LARGEST_TEXT = 2.0f

        /** Which of the two copies a finder returns first: the narrow one, then the roomy one. */
        const val NARROW = 0
        const val ROOMY = 1

        /** A dp of rounding, which measurement in two different columns can produce. */
        const val TOLERANCE = 1.0
    }
}
