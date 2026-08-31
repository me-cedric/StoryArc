package app.storyarc

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The Downloads shelf's own cell, which is the surface the defect was reported on.
 *
 * It had no behavioural test at all. `ShelvesDrawOneWellTest` next door reads the source and
 * checks that the substring `CoverlessWell(` appears in this file, and `:feature:library`'s
 * `CoverlessWellTest` composes Home's cell a module away — so replacing this cell's call with
 * `CoverlessWell(title = "", format = null)`, which draws nothing visible and is the reported
 * defect exactly, passed the entire suite. A grep is not a test of what a screen draws.
 *
 * What made it compose-able was giving [OnDeviceCover] its cover as a function instead of a
 * `LibraryViewModel`; that parameter's own comment carries the reasoning.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives at length: Robolectric's
 * legacy graphics measure a string as roughly a pixel per glyph, so text fits anywhere and any
 * assertion about it passes.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above this app's minimum, and nothing here has
// an API level in it.
@Config(sdk = [34])
class DownloadsCoverlessWellTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * A publication with no artwork says what it is, in the box where the cover would be.
     *
     * Two assertions rather than one, because the cell states the title twice over and only
     * one of the two is the well: the caption at the foot of the column says it as well, and it
     * said it before this fix while the box above stayed empty. So the title is expected
     * **twice** in the drawn tree — once in the well, once in the caption — and the format,
     * which nothing but the well names on this cell, is expected once.
     *
     * `useUnmergedTree`, because the well is deliberately silent to a screen reader; see the
     * test below. The unmerged tree is what was drawn, which is the claim here.
     */
    @Test
    fun `the downloads cell draws the well when there is no artwork`() {
        showCell()

        compose.onAllNodesWithText(TITLE, useUnmergedTree = true).assertCountEquals(2)
        compose.onNodeWithText(FORMAT, useUnmergedTree = true).assertIsDisplayed()
    }

    /**
     * And announces itself once, without the format.
     *
     * The cell is one spoken node — `combinedClickable` merges it — and the caption is what
     * labels it. A well that also spoke made this cell announce
     * `Foreign Codec, CBZ, Foreign Codec`: the title twice, and a format the caption does not
     * carry and never did. iOS's identical surface has been `.accessibilityHidden` all along
     * and its comment says why; `CoverlessWell` now does the Android equivalent for every
     * caller.
     */
    @Test
    fun `the downloads cell announces the title once and no format`() {
        showCell()

        compose.onNode(hasClickAction()).assertTextEquals(TITLE)
    }

    private fun showCell() {
        compose.setContent {
            StoryArcTheme {
                // The width the grid gives a cell on a phone. The cell fills what it is
                // handed, and a title wrapping against a whole window would prove nothing.
                Box(modifier = Modifier.width(COVER_WIDTH)) {
                    OnDeviceCover(
                        publication = publication(),
                        // What a publication with no cover answers forever.
                        cover = { _, _ -> null },
                        onOpen = {},
                        onRemove = null,
                    )
                }
            }
        }
    }

    private fun publication() = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$TITLE.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = TITLE,
        origin = MetadataOrigin.INFERRED,
    )

    private companion object {
        /** One of the emulator corpus's coverless fixtures, and a `CBZ`, as on the shelf. */
        const val TITLE = "Foreign Codec"
        val FORMAT = PublicationFormat.CBZ.displayName

        /** `design.md` §4's phone tier, so a title wraps against a width the app really uses. */
        val COVER_WIDTH = 104.dp
    }
}
