package app.storyarc.feature.library

import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 2.3: "the coverless well offers it".
 *
 * The well "draws a glyph and a format name and offers nothing", which is what made a
 * publication with no artwork a dead end — the reason this whole change exists. It is the
 * entry point now, and a page that offers no choice at all still draws exactly the hero it
 * drew before, which is the second half of the same promise.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class CoverlessWellOffersAChoiceTest {

    @get:Rule
    val compose = createComposeRule()

    private val bare = Publication(
        identity = PublicationIdentity(contentDigest = "bare"),
        format = PublicationFormat.M4B,
        displayTitle = "Ripped From A CD",
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `an empty well is the way to choose a cover`() {
        var asked = 0
        compose.setContent {
            StoryArcTheme {
                DetailHero(
                    publication = bare,
                    cover = null,
                    accent = null,
                    layout = DetailHeroLayout(isSideBySide = false, coverHeight = COVER_HEIGHT),
                    coverChoice = CoverChoice(onChoose = { asked++ }),
                ) {}
            }
        }
        compose.waitForIdle()

        // By the format's own name, which is the only text in the well. `useUnmergedTree` is
        // not needed here and that is the point: a well that acts is reachable, where the
        // decorative one carries `clearAndSetSemantics {}` and is not.
        compose.onNodeWithText("M4B").assertHasClickAction().performClick()
        // And said in words underneath, because a silently tappable well is one nobody taps.
        compose.onNodeWithText(CHOOSE).assertHasClickAction().performClick()

        assertEquals(2, asked)
    }

    @Test
    fun `a page that offers no choice draws the hero it always drew`() {
        compose.setContent {
            StoryArcTheme {
                DetailHero(
                    publication = bare,
                    cover = null,
                    accent = null,
                    layout = DetailHeroLayout(isSideBySide = false, coverHeight = COVER_HEIGHT),
                ) {}
            }
        }
        compose.waitForIdle()

        // The control for the case above. Without it, a well that had stopped being
        // decorative for any reason at all would pass that test.
        compose.onNodeWithText("M4B", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("M4B").assertDoesNotExist()
        compose.onNodeWithText(CHOOSE).assertDoesNotExist()
        compose.onNodeWithText(REMOVE).assertDoesNotExist()
    }

    @Test
    fun `a chosen cover can be removed, and says what moving the publication would cost`() {
        var removed = 0
        compose.setContent {
            StoryArcTheme {
                DetailHero(
                    publication = bare,
                    cover = null,
                    accent = null,
                    layout = DetailHeroLayout(isSideBySide = false, coverHeight = COVER_HEIGHT),
                    coverChoice = CoverChoice(
                        hasChosen = true,
                        isTiedToPath = true,
                        onChoose = {},
                        onRemove = { removed++ },
                    ),
                ) {}
            }
        }
        compose.waitForIdle()

        compose.onNodeWithText(TIED_TO_PATH).assertExists()
        compose.onNodeWithText(REMOVE).performClick()

        assertEquals(1, removed)
    }

    private companion object {
        val COVER_HEIGHT = androidx.compose.ui.unit.Dp(360f)
        const val CHOOSE = "Choose a cover"
        const val REMOVE = "Remove cover"
        const val TIED_TO_PATH = "Moving this publication loses the cover you chose."
    }
}
