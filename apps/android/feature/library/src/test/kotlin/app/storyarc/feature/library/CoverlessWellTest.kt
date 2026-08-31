package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.cover.CoverlessWell
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
 * A cover-shaped cell with no artwork in it says what the publication is.
 *
 * Two things are pinned here and they are different things. The first three cases are the
 * well's own contract — a title always, a format only when the surface names one — asserted
 * against [CoverlessWell] directly. The last is the defect: [HomeCoverArt] is one of the three
 * surfaces that ended at `cover?.let { Image(…) }` with no else branch, so it drew the sunken
 * surface and stopped. Composing it with a cover source that yields nothing is the state a
 * publication with no artwork is permanently in, and the title on screen is what was missing.
 *
 * Why Home and not Downloads, when Downloads is the shelf the defect was reported on:
 * `OnDeviceCover` is internal to `:app`, and `:app` declares neither Robolectric nor a Compose
 * test rule in `testImplementation` — the same wall `ShelvesAskOneRuleTest` documents. This
 * module has both, and [HomeCoverArt] is internal to it, so this is the one of the four
 * surfaces a unit test can actually compose. `:app`'s `ShelvesDrawOneWellTest` is what covers
 * the other three, by reading source, and it names why.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives at length: Robolectric's
 * legacy graphics measure a string as roughly a pixel per glyph, which makes text fit anywhere
 * and any assertion about it pass. The cell is given a real cover's width and proportion so
 * the four-line title has somewhere plausible to wrap.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above this app's minimum, and nothing here has
// an API level in it.
@Config(sdk = [34])
class CoverlessWellTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `a well names the publication`() {
        showWell(title = "Harbour Lights 01", format = "CBZ")

        compose.onNodeWithText("Harbour Lights 01").assertIsDisplayed()
    }

    @Test
    fun `a well names the format when the surface asks for it`() {
        showWell(title = "Harbour Lights 01", format = "CBZ")

        compose.onNodeWithText("CBZ").assertIsDisplayed()
    }

    /**
     * And says nothing about a format on a surface that passes none.
     *
     * This is the whole of what the parameter buys. A shelf of one series, or a Home card whose
     * caption is the title and how much is left, gains nothing from a label every cell around
     * it repeats — so the parameter has to be able to withhold it, not merely soften it.
     */
    @Test
    fun `a well with no format names none`() {
        showWell(title = "Harbour Lights 01", format = null)

        compose.onNodeWithText("CBZ").assertDoesNotExist()
        compose.onNodeWithText("Harbour Lights 01").assertIsDisplayed()
    }

    /**
     * Home's card, with no artwork to draw. The title is on screen.
     *
     * `cover` returns `null` for every request, which is what a publication with no cover does
     * forever — `LibraryViewModel.cover` answers `null` for one, and the card is redrawn with
     * that answer on every recomposition. Before this change the box was empty.
     */
    @Test
    fun `home's cover art draws the well when there is no artwork`() {
        compose.setContent {
            StoryArcTheme {
                HomeCoverArt(
                    publication = publication("Foreign Codec"),
                    cover = { _, _ -> null },
                    width = COVER_WIDTH,
                    modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f),
                )
            }
        }

        compose.onNodeWithText("Foreign Codec").assertIsDisplayed()
    }

    private fun showWell(title: String, format: String?) {
        compose.setContent {
            StoryArcTheme {
                // The frame the callers own: every one of the four already has a cover-shaped
                // box at the sunken surface, and the well paints only its contents.
                Box(modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f)) {
                    CoverlessWell(title = title, format = format)
                }
            }
        }
    }

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    private companion object {
        /** `design.md` §4's phone tier, so a title wraps against a width the app really uses. */
        val COVER_WIDTH = 104.dp
    }
}
