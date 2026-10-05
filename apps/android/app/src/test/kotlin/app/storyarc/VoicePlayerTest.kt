package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SkipUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The full player, drawn for the read-aloud voice.
 *
 * Task 13.2. `audio-playback`, *Both sources look the same*:
 *
 * > the surface, the controls and the lock-screen presentation are the same
 * > **AND** every control the player offers works, or is absent — none is present and
 * > refusing
 *
 * The surface is the same surface — this composes `PlayerScreen`, the one the narrated
 * player uses — and what changes is what the source declares: a skip that moves a sentence
 * and parts that state no length. Nothing in the screen asks which engine is speaking.
 *
 * Robolectric with native graphics, for the reason `PlayerSemanticsTest` sets out: legacy
 * graphics measure a glyph at about a pixel, so a control drawn off the edge would pass.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class VoicePlayerTest {

    @get:Rule
    val compose = createComposeRule()

    private fun spoken(
        parts: List<PlaybackPart> = listOf(PlaybackPart("The Harbour"), PlaybackPart("")),
        partIndex: Int = 0,
    ) = NowPlaying(
        publicationId = epub().id,
        title = "Harbour Lights 01",
        parts = parts,
        partIndex = partIndex,
        offsetMillis = 0,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.NORMAL,
        skipUnit = SkipUnit.SENTENCE,
    )

    private fun epub() = Publication(
        identity = PublicationIdentity(normalizedPath = "/books/harbour-lights-01.epub"),
        format = PublicationFormat.EPUB,
        displayTitle = "Harbour Lights 01",
        origin = MetadataOrigin.INFERRED,
    )

    @Composable
    private fun Player(playing: NowPlaying = spoken()) {
        StoryArcTheme {
            PlayerScreen(
                playing = playing,
                onToggle = {},
                onSkip = {},
                onSeek = {},
                onSeekSettled = {},
                onChooseChapter = {},
                onSpeed = {},
                sleep = null,
                onSleep = {},
                onBack = {},
                publication = epub(),
            )
        }
    }

    // MARK: - The transport

    @Test
    fun `the skip controls name the sentence they move, not a number of seconds`() {
        compose.setContent { Player() }

        compose.onNodeWithContentDescription("Previous sentence").assertIsDisplayed()
        compose.onNodeWithContentDescription("Next sentence").assertIsDisplayed()
    }

    @Test
    fun `no interval is stated on a control that does not move by one`() {
        compose.setContent { Player() }

        compose.onAllNodesWithText("15 s", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("30 s", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun `a narrated book still states its intervals, so the branch is the source's`() {
        compose.setContent {
            Player(
                playing = spoken(
                    parts = listOf(PlaybackPart("The Harbour")),
                ).copy(skipUnit = SkipUnit.SECONDS),
            )
        }

        compose.onNodeWithText("15 s", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("30 s", useUnmergedTree = true).assertIsDisplayed()
        compose.onAllNodesWithContentDescription("Previous sentence").assertCountEquals(0)
    }

    // MARK: - The chapter list

    @Test
    fun `a resource the contents did not name still reads as a chapter`() {
        compose.setContent { Player() }

        // The named part twice — the line under the artwork and its row in the list — and
        // the unnamed one once, as the row the contents left blank.
        compose.onAllNodesWithText("The Harbour").assertCountEquals(2)
        // Scrolled to, because the list is what scrolls away under the transport — see
        // `PlayerScreen`'s own note on why the transport is above it.
        compose.onNodeWithText("Chapter 2").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun `the chapter line names the unnamed resource the list names`() {
        compose.setContent { Player(playing = spoken(partIndex = 1)) }

        // Twice: the line under the artwork, and the row in the list.
        compose.onAllNodesWithText("Chapter 2").assertCountEquals(2)
    }

    // MARK: - Which publication the player draws

    /*
     * `playedPublication` is the app's half of what is playing. A read-aloud session is
     * never `PlayingBook.following` — see `carStartedBook` for why pointing the listening
     * writer at a reflowable book would be wrong — so without this rule the player drew the
     * coverless well for every voice session.
     */

    @Test
    fun `a book this app started is drawn from what it is following`() {
        val audiobook = epub()

        val drawn = playedPublication(spoken(), following = audiobook, library = emptyList())

        assertSame(audiobook, drawn)
    }

    @Test
    fun `a publication being read aloud is found in the library instead`() {
        val book = epub()

        val drawn = playedPublication(spoken(), following = null, library = listOf(book))

        assertSame(book, drawn)
    }

    @Test
    fun `an audiobook nothing here started stays coverless, which is the honest answer`() {
        val resumed = Publication(
            identity = PublicationIdentity(normalizedPath = "/audiobooks/sea-room.m4b"),
            format = PublicationFormat.M4B,
            displayTitle = "Sea Room",
            origin = MetadataOrigin.INFERRED,
        )
        val playing = spoken().copy(publicationId = resumed.id)

        assertNull(playedPublication(playing, following = null, library = listOf(resumed)))
    }

    @Test
    fun `a book the library does not hold is drawn from nothing`() {
        assertEquals(null, playedPublication(spoken(), following = null, library = emptyList()))
    }
}
