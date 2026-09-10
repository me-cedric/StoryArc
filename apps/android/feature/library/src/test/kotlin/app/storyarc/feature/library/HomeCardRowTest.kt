package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadState
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * That a row of Keep reading cards is one row and not three shapes.
 *
 * `home-screen`, *Every card in the row is the same size*: every card has "the same width
 * and the same height, whatever its title, its byline or its artwork", and "the resume
 * affordance sits at the same height on every card". The reader met the failure as blocks
 * that "seem to not be the same size every time", with the buttons at two heights.
 *
 * `HomeArtworkShapeTest` covers the artwork arithmetic. This covers what the layout does
 * with it, which is the half that broke: a card that sized itself to its own content.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h914dp")
class HomeCardRowTest {

    @get:Rule
    val compose = createComposeRule()

    private val cardWidth = 200.dp

    private fun entry(title: String, authors: List<String> = emptyList()) = HomeEntry(
        publication = Publication(
            identity = PublicationIdentity(contentDigest = title),
            format = PublicationFormat.CBZ,
            displayTitle = title,
            origin = MetadataOrigin.INFERRED,
            authors = authors,
        ),
        isReadableNow = true,
        pagesRemaining = 12,
        fraction = 0.4,
        state = ReadState.IN_PROGRESS,
    )

    /** A cover of an exact shape, so two cards can differ only in their artwork. */
    private fun cover(width: Int, height: Int): suspend (Publication, Int) -> Bitmap? =
        { _, _ -> Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888) }

    /** The row the carousel draws: one height, given to every card in it. */
    private fun row(
        left: Pair<HomeEntry, suspend (Publication, Int) -> Bitmap?>,
        right: Pair<HomeEntry, suspend (Publication, Int) -> Bitmap?>,
    ) {
        compose.setContent {
            StoryArcTheme {
                Row(
                    modifier = Modifier.height(homeHeroBlockHeight(cardWidth, fontScale = 1f)),
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                ) {
                    listOf(LEFT to left, RIGHT to right).forEach { (tag, card) ->
                        HomeKeepReadingCard(
                            entry = card.first,
                            cover = card.second,
                            width = cardWidth,
                            onResume = {},
                            onFinish = {},
                            onOpenNext = {},
                            modifier = Modifier.testTag(tag),
                        )
                    }
                }
            }
        }
    }

    private fun heightOf(tag: String) = compose.onNodeWithTag(tag).fetchSemanticsNode().size.height

    /**
     * How far the resume button's foot sits above its own card's foot.
     *
     * The button is found by which card it stands in rather than by its place in the
     * semantics tree, because both cards offer one and the tree's order is not the row's.
     */
    private fun footRoom(tag: String): Int {
        val card = compose.onNodeWithTag(tag).fetchSemanticsNode()
        val left = card.positionInRoot.x
        val right = left + card.size.width
        val button = compose.onAllNodesWithText(RESUME_LABEL)
            .fetchSemanticsNodes()
            .single { it.positionInRoot.x >= left && it.positionInRoot.x < right }

        return (card.positionInRoot.y + card.size.height).toInt() -
            (button.positionInRoot.y + button.size.height).toInt()
    }

    @Test
    fun twoCoversOfDifferentShapesGiveTwoCardsOfOneHeight() {
        row(
            entry("A Wide One") to cover(1000, 500),
            entry("A Tall One") to cover(500, 1500),
        )

        assertEquals(
            "A landscape cover and a portrait one gave two card heights.",
            heightOf(LEFT),
            heightOf(RIGHT),
        )
    }

    @Test
    fun theResumeButtonSitsTheSameDistanceFromEachCardsFoot() {
        row(
            entry("Short") to cover(800, 1200),
            entry(
                "A Considerably Longer Title That Wraps Onto A Second Line",
                authors = listOf("Someone Named"),
            ) to cover(800, 1200),
        )

        val plain = footRoom(LEFT)
        val crowded = footRoom(RIGHT)

        assertTrue(
            "One card has a byline and a title that wraps, and its Resume moved with them:" +
                " $plain px above its foot against $crowded px. A pixel is the height model" +
                " rounding; anything more is the caption pushing the button off the foot.",
            abs(plain - crowded) <= 1,
        )
    }

    private companion object {
        const val LEFT = "keep-reading-left"
        const val RIGHT = "keep-reading-right"
        const val RESUME_LABEL = "Resume"
    }
}
