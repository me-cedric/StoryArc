package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.RememberedShelf
import app.storyarc.core.model.RememberedShelfKind
import app.storyarc.core.model.Shelves
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.util.UUID

/**
 * A server shelf's card on Home draws the count its own fetch found, at once.
 *
 * `collections-and-reading-lists`: the card fetches the count lazily when it first appears.
 * The record keeps the count for the next launch, and this card must not wait for it.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class HomeShelfCountTest {

    @get:Rule
    val compose = createComposeRule()

    private val shelf = RememberedShelf(RememberedShelfKind.READING_LIST, UUID.randomUUID(), 9, "Crisis, in order")

    private val entry = HomeEntry(
        publication = Publication(
            identity = PublicationIdentity(contentDigest = "one"),
            format = PublicationFormat.CBZ,
            displayTitle = "One",
            origin = MetadataOrigin.INFERRED,
        ),
        isReadableNow = true,
        pagesRemaining = null,
        fraction = 0.0,
        state = ReadState.UNREAD,
    )

    @Test
    fun theCardDrawsTheCountItsFetchFound() {
        compose.setContent {
            StoryArcTheme {
                HomeScreen(
                    surface = HomeSurface(recentlyAdded = listOf(entry)),
                    cover = { _, _ -> null },
                    onOpen = {},
                    onResume = {},
                    onFinish = {},
                    onShowAll = {},
                    onOpenFile = {},
                    onAddFolder = {},
                    onAddCatalogue = {},
                    onAddKavita = {},
                    onAddShare = {},
                    shelves = HomeShelfIndex.assemble(
                        shelves = Shelves(),
                        publications = emptyList(),
                        remembered = listOf(shelf),
                        openableSources = mapOf(shelf.sourceId to "Kavita at home"),
                    ),
                    serverArtwork = {
                        HomeShelfArtworkOutcome(HomeShelfCoverPlan.Blank, counted = it.counted(12, finished = 5))
                    },
                )
            }
        }

        compose.onNodeWithContentDescription("Kavita at home · 12 titles", substring = true).assertExists()
    }
}
