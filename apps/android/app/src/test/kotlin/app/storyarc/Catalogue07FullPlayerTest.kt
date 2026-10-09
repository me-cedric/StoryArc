package app.storyarc

import androidx.compose.ui.test.junit4.v2.createComposeRule
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

    private fun draw(look: Look) = compose.catalogue("07-full-player", look) {
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
}
