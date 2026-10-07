package app.storyarc.core.playback

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import androidx.media3.common.MediaItem
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config

/**
 * The voice behind the player's one media session: one notification, and the first car row.
 *
 * Task 13.2. `audio-playback`, *One player for everything that speaks*: the voice used to post
 * a notification and a media session of its own, so a listener had two transports and a car
 * had no row for it. Now [PlaybackHost.startVoice] seats a [VoicePlayer] in [PlaybackService]'s
 * session, and the end of the voice seats the decoder again.
 *
 * `audiobooks-and-playback` 12.1, the read-aloud clause of *Listening in a car*: a read-aloud
 * session is on the car's list. The last two cases assert it through the service's own tree.
 *
 * Robolectric builds the service and runs its `onCreate`. No controller binds in this JVM, so
 * what is asserted is the session the service holds, which is what media3 draws the
 * notification, the lock screen and the car from.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlaybackServiceVoiceTest {

    private class Voice : PlayerSource {
        override val publicationId = "harbour-lights"
        override val title = "Harbour Lights"
        override val parts = listOf(PlaybackPart("The Harbour"), PlaybackPart("The Lights"))
        override val position = PlaybackPosition(1, 0)
        override val skipUnit = SkipUnit.SENTENCE
        var state = PlaybackSession().started()
        override val session: PlaybackSession get() = state
        override val speed = PlaybackSpeed.NORMAL
        override var onChange: (() -> Unit)? = null
        override var onInterruptionEnd: ((mayResume: Boolean) -> Unit)? = null
        val skipped = mutableListOf<SkipDirection>()
        override fun play() { state = state.started(); onChange?.invoke() }
        override fun pause() { state = state.pausedByListener(); onChange?.invoke() }
        override fun stop() { state = state.stopped(); onChange?.invoke() }
        override fun seek(to: PlaybackPosition) = Unit
        override fun setSpeed(speed: PlaybackSpeed) = Unit
        override fun skip(direction: SkipDirection, byMillis: Long) { skipped += direction }
    }

    private val context = RuntimeEnvironment.getApplication()
    private val voice = Voice()
    private var service: ServiceController<PlaybackService>? = null

    private val reopen: PendingIntent =
        PendingIntent.getActivity(context, 0, Intent(), PendingIntent.FLAG_IMMUTABLE)

    @Before
    fun noServiceToBind() {
        shadowOf(context).declareComponentUnbindable(ComponentName(context, PlaybackService::class.java))
    }

    @After
    fun quiet() {
        PlaybackHost.stopVoice(voice)
        service?.destroy()
        service = null
    }

    private fun running(): PlaybackService =
        Robolectric.buildService(PlaybackService::class.java).create().also { service = it }.get()

    private fun PlaybackService.labels() = buttons.map { it.displayName.toString() }

    @Test
    fun `a speaking voice is the player of the one media session`() {
        val running = running()

        PlaybackHost.startVoice(context, voice, reopen)

        val session = requireNotNull(running.session)
        assertTrue("the voice is not behind the session", session.player is VoicePlayer)
        assertEquals("Harbour Lights", session.player.mediaMetadata.title)
        assertSame("a tap on the notification does not go back to the book", reopen, session.sessionActivity)
    }

    /** A voice that started before the service ran is seated when the service starts. */
    @Test
    fun `a service that starts while a voice speaks seats the voice`() {
        PlaybackHost.startVoice(context, voice, reopen)

        val running = running()

        assertTrue(requireNotNull(running.session).player is VoicePlayer)
    }

    @Test
    fun `the end of the voice seats the decoder again`() {
        val running = running()
        PlaybackHost.startVoice(context, voice, reopen)

        PlaybackHost.stopVoice(voice)

        val session = requireNotNull(running.session)
        assertFalse("the voice outlived its session", session.player is VoicePlayer)
        assertEquals(0, session.player.mediaItemCount)
        assertEquals(listOf("Back 15 seconds", "Forward 30 seconds"), running.labels())
    }

    /**
     * One session: the voice displaces a narrated file, so the decoder is silenced and
     * emptied when the voice is seated, and the decoder seated again after it holds nothing.
     */
    @Test
    fun `seating the voice silences the decoder it displaces`() {
        val running = running()
        val session = requireNotNull(running.session)
        session.player.setMediaItem(MediaItem.fromUri("file:///books/sea-room.m4b"))

        PlaybackHost.startVoice(context, voice, reopen)
        PlaybackHost.stopVoice(voice)

        assertEquals("the displaced file is still loaded", 0, session.player.mediaItemCount)
    }

    /** `ebook-reader`: the controls offer "play, pause, and sentence skip". */
    @Test
    fun `the notification's outer buttons move a sentence`() {
        val running = running()
        PlaybackHost.startVoice(context, voice, reopen)

        assertEquals(listOf("Previous sentence", "Next sentence"), running.labels())

        running.skip(SkipDirection.BACK)
        running.skip(SkipDirection.FORWARD)

        assertEquals(listOf(SkipDirection.BACK, SkipDirection.FORWARD), voice.skipped)
    }

    @Test
    fun `the live voice is the first car row`() {
        val running = running()
        PlaybackHost.publishCarLibrary(
            context,
            listOf(CarBook(id = "sea-room", title = "Sea Room", uris = listOf("file:///sea-room.m4b"))),
        )
        PlaybackHost.startVoice(context, voice, reopen)

        val rows = running.carRows()

        assertEquals(listOf("harbour-lights", "sea-room"), rows.map { it.id })
        assertEquals("The Lights", rows.first().partTitle)
    }

    @Test
    fun `a voice that has ended leaves the car list`() {
        val running = running()
        PlaybackHost.startVoice(context, voice, reopen)

        PlaybackHost.stopVoice(voice)

        assertNull(running.carRows().firstOrNull { it.id == "harbour-lights" })
    }
}
