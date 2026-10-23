package app.storyarc

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.unit.dp
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Fixtures
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Catalogue entry 7: the full audiobook player, mid-chapter, with a cover and a chapter list. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue07FullPlayerTest {

    @get:Rule
    val compose = createComposeRule()

    private val book = Publication(
        identity = PublicationIdentity(normalizedPath = "/audiobooks/sea-room.m4b"),
        format = PublicationFormat.M4B,
        displayTitle = "Sea Room",
        origin = MetadataOrigin.INFERRED,
    )

    private val playing = NowPlaying(
        publicationId = book.id,
        title = "Sea Room",
        parts = listOf(
            PlaybackPart("The Harbour", PlaybackDuration.Known(1_320_000)),
            PlaybackPart("The Crossing", PlaybackDuration.Known(2_340_000)),
            PlaybackPart("The Return", PlaybackDuration.Known(1_740_000)),
        ),
        partIndex = 1,
        offsetMillis = 1_320_000 + 612_000,
        partStartMillis = 1_320_000,
        session = PlaybackSession().started(),
        speed = PlaybackSpeed.of(1.25),
    )

    private fun draw(look: Look) = compose.catalogue("07-full-player", look) { Player() }

    /**
     * Entry 7b: the player on a short phone, 411 x 731 dp, inside the chrome the app draws
     * there: a 24 dp status bar above, and below it the 80 dp navigation bar over a 48 dp
     * system bar. The artwork gives up height so the transport stays on the first screen,
     * which `audio-playback` requires (task 28.12 of `close-the-audited-gaps`).
     */
    @Test
    @Config(qualifiers = "w411dp-h731dp-xhdpi")
    fun shortPhone() = compose.catalogue(
        "07b-full-player-short-phone",
        Look.Light,
        act = {
            val visibleBottom = with(density) { (731 - CHROME_BELOW).dp.toPx() }
            val forward = onNodeWithContentDescription("Forward 30 seconds").fetchSemanticsNode()
            assertTrue(
                "the skip control ends at ${forward.boundsInRoot.bottom} px, under the bar at $visibleBottom px",
                forward.boundsInRoot.bottom <= visibleBottom,
            )
        },
    ) {
        Box(Modifier.fillMaxSize().padding(top = 24.dp, bottom = CHROME_BELOW.dp)) { Player() }
    }

    @Composable
    private fun Player() {
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
            publication = book,
            cover = { _, _ -> Fixtures.cover(3) },
        )
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    @Test
    fun largest() = draw(Look.Largest)

    private companion object {
        /** The navigation bar over the system's own bar, in dp. */
        const val CHROME_BELOW = 80 + 48
    }
}
