package app.storyarc.feature.library

import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
 * [HomeCoverArt], the one coverless-well caller that lives in this module rather than in
 * `:core:designsystem` or `:app`.
 *
 * The well's own contract — a format's glyph and name, drawn by one of two overloads — is
 * asserted once, in `:core:designsystem`'s own `CoverlessWellTest`, pure and with no window.
 * What that suite cannot reach is whether *this* composable still asks for it, and asks for
 * the right overload, after a publication arrives with no cover: `cover` answers `null` for
 * one, and the card is redrawn with that answer on every recomposition.
 *
 * Before `audiobooks-and-playback` task 16.8, this surface named the title and no format —
 * "nothing on Home names one" was the rule. Task 16.8 changed the rule itself: every
 * per-publication well now names the format instead of repeating a title the caption beside
 * it already states, and this test was rewritten to assert the new rule rather than the one
 * it replaced.
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
    fun `home's cover art draws the well when there is no artwork, naming the format`() {
        compose.setContent {
            StoryArcTheme {
                HomeCoverArt(
                    publication = publication(TITLE, PublicationFormat.CBZ),
                    cover = { _, _ -> null },
                    width = COVER_WIDTH,
                    modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f),
                )
            }
        }

        compose.onNodeWithText(FORMAT, useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText(TITLE, useUnmergedTree = true).assertDoesNotExist()
    }

    /**
     * The format drawn is *this* publication's, not a constant — a card showing a CBZ's
     * glyph for every format would pass the test above by accident.
     */
    @Test
    fun `the format named is the publication's own`() {
        compose.setContent {
            StoryArcTheme {
                HomeCoverArt(
                    publication = publication(TITLE, PublicationFormat.EPUB),
                    cover = { _, _ -> null },
                    width = COVER_WIDTH,
                    modifier = Modifier.width(COVER_WIDTH).aspectRatio(2f / 3f),
                )
            }
        }

        compose.onNodeWithText(PublicationFormat.EPUB.displayName, useUnmergedTree = true)
            .assertIsDisplayed()
        compose.onNodeWithText(FORMAT, useUnmergedTree = true).assertDoesNotExist()
    }

    private fun publication(title: String, format: PublicationFormat) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.${format.name.lowercase()}"),
        format = format,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    private companion object {
        const val TITLE = "Foreign Codec"
        val FORMAT = PublicationFormat.CBZ.displayName

        /** `design.md` §4's phone tier, so the card is measured at a width the app really uses. */
        val COVER_WIDTH = 104.dp
    }
}
