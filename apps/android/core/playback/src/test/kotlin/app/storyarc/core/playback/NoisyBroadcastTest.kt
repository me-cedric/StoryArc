package app.storyarc.core.playback

import android.content.ComponentName
import android.content.Intent
import android.media.AudioManager
import android.os.Looper
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
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
 * Headphones pulled out, as the system sends it, to the player the service builds.
 *
 * Task 3.9. `PlayerInterruptionTest` asserts the decision: media3 names `AUDIO_BECOMING_NOISY`
 * and the session records the listener's pause. It feeds that name to a fake player, so it
 * cannot tell whether the player the service builds ever hears the broadcast. This sends
 * `ACTION_AUDIO_BECOMING_NOISY` through the framework to the real [ExoPlayer] that
 * [PlaybackService.onCreate] makes, with a real [AudiobookSource] and [PlaybackCentre] on it.
 *
 * Dropping `setHandleAudioBecomingNoisy(true)` from the service leaves the book playing out
 * loud, and the first case fails by name.
 *
 * The ExoPlayer here has no media and never buffers, so `isPlaying` is false throughout and
 * what is read is `playWhenReady`, which is the fact the listener's pause changes. A decoder
 * on a device is `PlaybackNoisyInstrumentedTest`'s.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class NoisyBroadcastTest {

    private val context = RuntimeEnvironment.getApplication()
    private var service: ServiceController<PlaybackService>? = null

    @Before
    fun noServiceToBind() {
        shadowOf(context).declareComponentUnbindable(ComponentName(context, PlaybackService::class.java))
    }

    @After
    fun quiet() {
        service?.destroy()
        service = null
    }

    private class Listening(val exo: ExoPlayer, val source: AudiobookSource, val centre: PlaybackCentre) {
        val reasons = mutableListOf<Int>()
    }

    /** The service's own player, wanting audio, with a source and a centre watching it. */
    private fun listening(): Listening {
        val running = Robolectric.buildService(PlaybackService::class.java).create().also { service = it }.get()
        val seated = requireNotNull(running.session).player
        val exo = (seated as ChapterSeekingPlayer).wrappedPlayer as ExoPlayer
        val book = Audiobook(
            id = "sea-room",
            title = "Sea Room",
            sources = listOf(Audiobook.AudioPart("file:///sea-room.m4b", "Sea Room")),
        )
        val source = AudiobookSource(book, exo)
        val centre = PlaybackCentre()
        val listening = Listening(exo, source, centre)
        exo.addListener(object : Player.Listener {
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                listening.reasons += reason
            }
        })
        exo.playWhenReady = true
        source.attach()
        centre.attach(source)
        awaitNoisyReceiver()
        return listening
    }

    /**
     * media3 registers its noisy receiver from a background looper, so a broadcast sent at once
     * can arrive before anyone listens. Under a loaded suite run, that lost the first broadcast.
     */
    private fun awaitNoisyReceiver() {
        val deadline = System.nanoTime() + RECEIVER_WAIT_NANOS
        val noisy = AudioManager.ACTION_AUDIO_BECOMING_NOISY
        while (shadowOf(context).registeredReceivers.none { it.intentFilter.hasAction(noisy) }) {
            check(System.nanoTime() < deadline) { "the player never listened for the noisy broadcast" }
            Thread.sleep(RECEIVER_POLL_MILLIS)
        }
    }

    private fun noisy() {
        context.sendBroadcast(Intent(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun `the broadcast pauses the service's player, and the session records the listener's pause`() {
        val listening = listening()
        assertTrue("the player was never asked to play", listening.exo.playWhenReady)

        noisy()

        assertFalse("the player went on wanting audio out of the speaker", listening.exo.playWhenReady)
        assertEquals(
            "the player did not name the broadcast as its reason",
            Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_BECOMING_NOISY,
            listening.reasons.last(),
        )
        assertEquals(PlaybackState.PAUSED, listening.source.session.state)
        assertEquals(PauseCause.LISTENER, listening.source.session.pausedBy)
        assertNotNull("the book is paused, not ended", listening.centre.nowPlaying)
    }

    /**
     * "It does not resume by itself when they are reconnected." Reconnecting sends no
     * broadcast media3 acts on, and the session holds the listener's pause, so the table
     * answers nothing to the end of an interruption.
     */
    @Test
    fun `nothing the platform sends afterwards starts it again`() {
        val listening = listening()
        noisy()

        context.sendBroadcast(Intent(Intent.ACTION_HEADSET_PLUG).putExtra("state", 1))
        shadowOf(Looper.getMainLooper()).idle()
        listening.centre.endInterruption(mayResume = true)

        assertFalse("the headphones going back in started the book", listening.exo.playWhenReady)
        assertEquals(PlaybackState.PAUSED, listening.source.session.state)
        assertEquals(PauseCause.LISTENER, listening.source.session.pausedBy)
    }

    @Test
    fun `a second broadcast changes nothing`() {
        val listening = listening()
        noisy()
        val before = listening.reasons.size

        noisy()

        assertEquals("a second pull reported a second pause", before, listening.reasons.size)
        assertFalse(listening.exo.playWhenReady)
    }

    private companion object {
        const val RECEIVER_WAIT_NANOS = 5_000_000_000L
        const val RECEIVER_POLL_MILLIS = 10L
    }
}
