package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.KavitaCard
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.KavitaCardStore
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A downloaded Kavita title states its status and its rating with no server answering.
 *
 * `kavita-server`: "when a downloaded Kavita publication is opened with the server
 * unreachable, the cached server metadata is displayed, not the file's embedded metadata".
 * The other five fields that requirement names reach the page through `KavitaCard.appliedTo`
 * and are asserted where that is; these two cannot -- `Publication` has no slot for either --
 * so this is the only place that says they are drawn at all.
 *
 * Composed against the real store rather than a fake: what is being claimed is that the card
 * written when the chapter was kept is the card this screen reads, and a stub handed straight
 * to the composable would prove the formatting and nothing else.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34])
class KavitaCardFactsTest {

    @get:Rule
    val compose = createComposeRule()

    private val store =
        KavitaCardStore.open(ApplicationProvider.getApplicationContext())

    private fun card(
        ageRating: Int,
        publicationStatus: Int,
        publicationId: String = "p1",
    ) = KavitaCard(
        publicationId = publicationId,
        downloadId = "d1",
        sourceId = "s",
        seriesId = 7,
        chapterId = 1,
        seriesName = "Tidal Reach",
        chapterName = "The Harbour",
        ageRating = ageRating,
        publicationStatus = publicationStatus,
    )

    @Test
    fun `the status and the rating the card kept are both on the page`() {
        // Kavita's own numbers: 2 is `Completed` and 10 is `Mature 17+`.
        store.save(card(ageRating = 10, publicationStatus = 2))

        compose.setContent { StoryArcTheme { KavitaCardFacts("p1") } }

        // Each is a named line rather than a bare value, which is the whole reason they do
        // not join the run of facts: "Mature 17+" alone reads as a genre.
        compose.onNodeWithText("Status: Completed").assertExists()
        compose.onNodeWithText("Age rating: Mature 17+").assertExists()
    }

    @Test
    fun `a card that stated neither draws neither line`() {
        // Zero is Kavita's `Unknown` rating and -1 is outside its status table -- the two
        // values a card written before these fields existed comes back with. Saying "Status:
        // Ongoing" here would be the app stating something no server ever did.
        store.save(card(ageRating = 0, publicationStatus = -1))

        compose.setContent { StoryArcTheme { KavitaCardFacts("p1") } }

        compose.onNodeWithText("Status: Ongoing").assertDoesNotExist()
        compose.onNodeWithText("Age rating: Unknown").assertDoesNotExist()
    }

    @Test
    fun `a publication with no card at all draws nothing`() {
        // Most of the shelf: a file in a picked folder has no Kavita card, and an empty block
        // under its description would be the page reserving room for a server it never had.
        store.reset()

        compose.setContent { StoryArcTheme { KavitaCardFacts("p1") } }

        compose.onNodeWithText("Status: Completed").assertDoesNotExist()
        compose.onNodeWithText("Age rating: Mature 17+").assertDoesNotExist()
    }

    @Test
    fun `the detail page draws them, not just the block on its own`() {
        // The wiring, which is where the defect would live. `KavitaCardFacts` drawing two
        // lines proves nothing if the page never calls it, and deleting that one call leaves
        // every other test in this file green.
        val book = downloaded()
        store.save(card(ageRating = 10, publicationStatus = 2, publicationId = book.id))

        compose.setContent {
            StoryArcTheme {
                DetailMainPane(
                    publication = book,
                    cover = null,
                    accent = null,
                    action = PrimaryAction.READ,
                    provenance = Provenance(
                        place = Provenance.Place.DEVICE,
                        libraryName = null,
                        readiness = Provenance.Readiness.READY,
                        isAlsoElsewhere = false,
                    ),
                    downloadFraction = null,
                    onRead = {},
                    onDownload = null,
                )
            }
        }

        compose.onNodeWithText("Status: Completed").assertExists()
        compose.onNodeWithText("Age rating: Mature 17+").assertExists()
    }

    /**
     * A downloaded publication, whose own `id` the card is then filed under.
     *
     * The card is looked up by `Publication.id`, which is the identity's stable id rather
     * than anything a test may name -- the same key `LibraryViewModel` uses when it lays a
     * card over a download it has just walked to. Taking the id from the publication is what
     * makes this an assertion about the lookup instead of about a string.
     */
    private fun downloaded() = Publication(
        identity = PublicationIdentity(contentDigest = "p1"),
        format = PublicationFormat.CBZ,
        displayTitle = "The Harbour",
        series = "Tidal Reach",
        origin = MetadataOrigin.AUTHORITATIVE,
    )
}
