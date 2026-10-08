package app.storyarc

import android.graphics.Bitmap
import androidx.compose.ui.test.junit4.v2.createComposeRule
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
import org.robolectric.annotation.GraphicsMode

/**
 * `audiobooks-and-playback` task 4.4b: the picture for the system's own controls is drawn when a
 * session starts, with no player screen composed.
 *
 * What a host test can say is that [SessionArtwork] runs the same [PlayerArtwork] for the book
 * being played, at the size the player draws it, and for no book draws nothing. The proof is the
 * cover question [PlayerArtwork] asks before it draws: it is asked for this book, at the size the
 * shelves ask for, and once. Robolectric has no renderer to read the finished picture back from,
 * which `PlayerSemanticsTest` notes for the same reason, so that the shade then shows it is the
 * emulator's to prove.
 *
 * Robolectric with native graphics, for the reason `PlayerSemanticsTest` sets out.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37. A phone window, because it is the narrowest case.
@Config(sdk = [34], qualifiers = "w360dp-h740dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SessionArtworkTest {

    @get:Rule
    val compose = createComposeRule()

    private fun book(id: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$id"),
        format = PublicationFormat.M4B,
        displayTitle = id,
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private val asked = mutableListOf<Pair<String, Int>>()

    private fun drawn(publication: Publication?) {
        compose.setContent {
            StoryArcTheme {
                SessionArtwork(
                    publication = publication,
                    cover = { asking, pixels ->
                        asked += asking.id to pixels
                        null as Bitmap?
                    },
                    onArtwork = {},
                )
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun `the book being played has its artwork drawn with no player screen`() {
        val sea = book("sea-room")

        drawn(sea)

        assertEquals(listOf(sea.id to 512), asked)
    }

    @Test
    fun `nothing playing draws no artwork`() {
        drawn(null)

        assertEquals(emptyList<Pair<String, Int>>(), asked)
    }
}
