package app.storyarc.feature.library

import androidx.compose.runtime.Composable
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The publication page draws the chapter list, and the list is the way into a chapter.
 *
 * `DetailChaptersTest` pins what the rows say; this pins that the page says it. The whole
 * requirement is that a listener sees the chapters **before** starting the book, so a block
 * that draws correctly and is never called would satisfy every decision and no listener.
 *
 * Composed as [DetailMainPane] rather than as the block alone, for the reason
 * `KavitaCardFactsTest` gives: deleting the one call is the edit that reintroduces the
 * defect, and it must not leave this file green.
 *
 * `GraphicsMode.NATIVE` for the reason `ListOrderChipsWrapTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
class PublicationChaptersTest {

    @get:Rule
    val compose = createComposeRule()

    private val book = Publication(
        identity = PublicationIdentity(contentDigest = "sea-room"),
        format = PublicationFormat.M4B,
        displayTitle = "Sea Room",
        origin = MetadataOrigin.INFERRED,
    )

    private fun part(title: String, millis: Long?) = AudiobookPart(title, millis)

    private val three = listOf(
        part("The Harbour", 120_000),
        part("The Crossing", 300_000),
        part("The Return", 240_000),
    )

    private fun page(
        action: PrimaryAction,
        chapters: List<AudiobookPart>,
        stoppedIn: Int?,
        onRead: () -> Unit = {},
        onListenFrom: (Int) -> Unit = {},
        publication: Publication = book,
    ): @Composable () -> Unit = {
        DetailMainPane(
            publication = publication,
            cover = null,
            accent = null,
            action = action,
            provenance = Provenance(
                place = Provenance.Place.DEVICE,
                libraryName = null,
                readiness = Provenance.Readiness.READY,
                isAlsoElsewhere = false,
            ),
            downloadFraction = null,
            chapters = chapters,
            stoppedIn = stoppedIn,
            onRead = onRead,
            onListenFrom = onListenFrom,
            onDownload = null,
        )
    }

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { StoryArcTheme { content() } }
    }

    /** The row named [title] announces [value] as what it is worth listening to. */
    private fun assertRowValue(title: String, value: String) {
        compose.onNodeWithText(title).assert(
            SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value),
        )
    }

    @Test
    fun `the page lists every chapter with its title and its duration`() {
        show(page(PrimaryAction.LISTEN, three, stoppedIn = null))

        compose.onNodeWithText("The Harbour").assertIsDisplayed()
        compose.onNodeWithText("The Crossing").assertIsDisplayed()
        compose.onNodeWithText("The Return").assertIsDisplayed()
        // The duration is the row's **value**, which is what `audio-playback` asks a screen
        // reader to hear. One `clock` writes it, for this page and for the player, in the
        // form iOS also draws.
        assertRowValue("The Harbour", "2:00")
        assertRowValue("The Crossing", "5:00")
        assertRowValue("The Return", "4:00")
    }

    @Test
    fun `the chapter in progress and the ones finished are marked`() {
        show(
            page(
                PrimaryAction.CONTINUE_LISTENING,
                three,
                stoppedIn = 1,
            ),
        )

        compose.onNodeWithText("Finished").assertIsDisplayed()
        compose.onNodeWithText("In progress").assertIsDisplayed()
    }

    @Test
    fun `choosing a chapter starts there, and does not resume where the book was left`() {
        var chosen: Int? = null
        var resumed = false
        show(
            page(
                PrimaryAction.CONTINUE_LISTENING,
                three,
                stoppedIn = 0,
                onRead = { resumed = true },
                onListenFrom = { chosen = it },
            ),
        )

        compose.onNodeWithText("The Crossing").performClick()

        assertEquals(1, chosen)
        // The saved position is a parameter this page reads and never writes, and resuming is
        // the other verb. A row that called it would land the listener where they already
        // were, which is the half of the scenario a list of clickable rows gets wrong.
        assertEquals(false, resumed)
    }

    @Test
    fun `a single-part audiobook states its duration and draws no list`() {
        show(page(PrimaryAction.LISTEN, listOf(part("Sea Room", 5_400_000)), stoppedIn = null))

        compose.onNodeWithText("Duration 1:30:00").assertIsDisplayed()
        compose.onNodeWithText("Chapters").assertDoesNotExist()
    }

    @Test
    fun `the primary action names the chapter it resumes inside`() {
        show(
            page(
                PrimaryAction.CONTINUE_LISTENING,
                three,
                stoppedIn = 2,
            ),
        )

        compose.onNodeWithText("Continue “The Return”").assertIsDisplayed()
    }

    @Test
    fun `an audiobook never started offers to start it, naming no chapter`() {
        show(page(PrimaryAction.LISTEN, three, stoppedIn = null))

        compose.onNodeWithText("Listen").assertIsDisplayed()
        compose.onNodeWithText("Continue “The Harbour”").assertDoesNotExist()
    }

    @Test
    fun `a comic never grows a chapter list, whatever it is handed`() {
        // The rule lives on the page, not at the call site. A caller that passed an
        // audiobook's parts alongside a comic would otherwise print a chapter list under a
        // comic, and nothing in this module would notice.
        val comic = Publication(
            identity = PublicationIdentity(contentDigest = "bright-panels"),
            format = PublicationFormat.CBZ,
            displayTitle = "Bright Panels",
            origin = MetadataOrigin.INFERRED,
        )
        show(page(PrimaryAction.READ, three, stoppedIn = 1, publication = comic))

        compose.onNodeWithText("Chapters").assertDoesNotExist()
        compose.onNodeWithText("The Harbour").assertDoesNotExist()
    }

    @Test
    fun `a publication with no chapters at all draws no heading`() {
        // Most of the shelf. A comic's page must not reserve room for a list it will never
        // have, which is the same rule `KavitaCardFacts` follows one block below.
        var chosen: Int? = null
        show(page(PrimaryAction.READ, emptyList(), stoppedIn = null, onListenFrom = { chosen = it }))

        compose.onNodeWithText("Chapters").assertDoesNotExist()
        assertNull(chosen)
    }
}
