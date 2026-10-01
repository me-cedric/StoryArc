package app.storyarc.core.playback

import android.os.Looper
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * A chapter mark inside one file is written when the audio crosses it.
 *
 * `audio-playback`, *Where a listening position is written*: a crossing into another part is
 * written "at that moment". A folder crosses with a media3 transition callback. A mark inside
 * one file raises none, so [PlaybackHost] waits for [NowPlaying.untilPartEndsMillis] and then
 * republishes, and [PlaybackCentre.publish] sees the new part and writes.
 *
 * Robolectric because a `MediaItem` reaches `Uri.parse`, and because the wait runs on the
 * main looper, which the last case moves forward by hand.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class PartCrossingWakeTest {

    private fun playing(
        offsetMillis: Long,
        session: PlaybackSession = PlaybackSession().started(),
        duration: PlaybackDuration = PlaybackDuration.Known(120_000),
        speed: PlaybackSpeed = PlaybackSpeed.NORMAL,
    ) = NowPlaying(
        publicationId = "sea-room",
        title = "Sea Room",
        parts = listOf(PlaybackPart("The Harbour", duration), PlaybackPart("The Crossing")),
        partIndex = 0,
        offsetMillis = offsetMillis,
        session = session,
        speed = speed,
    )

    @Test
    fun `the wait is the time left in the part, at the playing speed`() {
        assertEquals(30_000L, playing(offsetMillis = 60_000, speed = PlaybackSpeed.of(2.0)).untilPartEndsMillis)
    }

    @Test
    fun `a paused book waits for nothing`() {
        val paused = PlaybackSession().started().pausedByListener()

        assertNull(playing(offsetMillis = 60_000, session = paused).untilPartEndsMillis)
    }

    @Test
    fun `a part that states no length waits for nothing`() {
        assertNull(playing(offsetMillis = 60_000, duration = PlaybackDuration.Unknown).untilPartEndsMillis)
    }

    @Test
    fun `a chapter mark crossed inside one file is written when the audio reaches it`() {
        val written = mutableListOf<PlaybackPosition>()
        val player = FakePlayer()
        val source = AudiobookSource(
            Audiobook(
                id = "sea-room",
                title = "Sea Room",
                sources = listOf(Audiobook.AudioPart("file:///sea-room.m4b", "Sea Room")),
            ),
            player,
        )
        source.prepare()
        PlaybackHost.recordPosition = { _, at, _ -> written += at }
        PlaybackHost.centre.start(source)
        try {
            player.measureFile(420_000)
            player.describeChapters(
                Triple("The Harbour", 0L, 120_000L),
                Triple("The Crossing", 120_000L, 420_000L),
            )
            // Ten seconds before the mark. The seek publishes, and that publish sets the wait.
            PlaybackHost.seek(PlaybackPosition(0, 110_000))
            // The clock runs on past the mark. `reach` raises no callback, as a clock does not.
            player.reach(121_000)

            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10_500))

            assertEquals(listOf(PlaybackPosition(1, 1_000)), written)
        } finally {
            // The host is an object. A source or a hook left in it is the next test's.
            PlaybackHost.recordPosition = null
            PlaybackHost.stop()
        }
    }
}
