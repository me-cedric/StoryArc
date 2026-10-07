package app.storyarc.core.playback

import android.content.ComponentName
import android.os.Looper
import java.time.Duration
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The voice drives the one player, and is still answered for by the voice's own host.
 *
 * Task 13.2 puts the read-aloud voice into [PlaybackHost]'s centre, which is what gives it
 * the compact bar and the full player. That raises a question `audio-playback` and
 * `ebook-reader` answer differently from each other, and getting it wrong is silent:
 *
 * - `audio-playback` wants **one** session, so the voice belongs in this centre.
 * - `ebook-reader` wants a listener whose **voice** was stopped by opening another
 *   publication to be told so, and [SpokenAudio] decides that from the *kind* of speaker it
 *   silenced. This host is the [SpokenAudio.Kind.NARRATOR].
 *
 * So a voice reported from here would be silenced as though a narrated file had been, and
 * the word would never be shown. [PlaybackHost.speaking] answers null while the voice holds
 * the session for exactly that reason, and `ReadAloudHost` — the `VOICE` — answers instead.
 *
 * Robolectric because [PlaybackHost] runs on `Dispatchers.Main.immediate`, which needs a
 * main looper. The source has no engine in it: what is under test is the host's own rule.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlaybackHostVoiceTest {

    private class Voice(override val skipUnit: SkipUnit = SkipUnit.SENTENCE) : PlayerSource {
        override val publicationId = "harbour-lights"
        override val title = "Harbour Lights"
        override val parts = listOf(PlaybackPart("Chapter One"))
        override val position = PlaybackPosition(0, 0)

        /** Every volume the sleep timer asked for, in order. */
        val volumes = mutableListOf<Float>()
        override fun setVolume(gain: Float) { volumes += gain }
        var state = PlaybackSession().started()
        override val session: PlaybackSession get() = state
        override val speed = PlaybackSpeed.NORMAL
        override var onChange: (() -> Unit)? = null
        override var onInterruptionEnd: ((mayResume: Boolean) -> Unit)? = null
        override fun play() { state = state.started(); onChange?.invoke() }
        override fun pause() { state = state.pausedByListener(); onChange?.invoke() }
        override fun stop() { state = state.stopped(); onChange?.invoke() }
        override fun seek(to: PlaybackPosition) = Unit
        override fun setSpeed(speed: PlaybackSpeed) = Unit
    }

    private val voice = Voice()

    private val context = RuntimeEnvironment.getApplication()

    /**
     * No service binds in this JVM. [PlaybackHost.startVoice] binds a controller so the media
     * service runs, and Robolectric would otherwise connect it with no component name.
     */
    @Before
    fun noServiceToBind() {
        shadowOf(context).declareComponentUnbindable(ComponentName(context, PlaybackService::class.java))
    }

    @After
    fun tearDown() {
        PlaybackHost.stopVoice(voice)
    }

    @Test
    fun `a started voice becomes the one session every surface reads`() {
        PlaybackHost.startVoice(context, voice)

        assertEquals("harbour-lights", PlaybackHost.nowPlaying.value?.publicationId)
        assertEquals(SkipUnit.SENTENCE, PlaybackHost.nowPlaying.value?.skipUnit)
    }

    @Test
    fun `the narrator's host does not answer for a voice it is only carrying`() {
        PlaybackHost.startVoice(context, voice)

        assertNull(PlaybackHost.speaking)
    }

    @Test
    fun `the voice's own teardown takes the session off the player`() {
        PlaybackHost.startVoice(context, voice)

        PlaybackHost.stopVoice(voice)

        assertNull(PlaybackHost.nowPlaying.value)
    }

    @Test
    fun `a stop for a voice this centre no longer holds leaves the session alone`() {
        val displaced = Voice()
        PlaybackHost.startVoice(context, voice)

        PlaybackHost.stopVoice(displaced)

        assertEquals("harbour-lights", PlaybackHost.nowPlaying.value?.publicationId)
    }

    // MARK: - The sleep timer's fade

    /*
     * Task 13.6, D19 and O20. The countdown is the host's, and it asks the source for its
     * volume on every tick. A voice fades across the last ten seconds; a source that moves by
     * seconds keeps the thirty-second fade. Twenty seconds on the timer, ten and a half of
     * them gone: nine and a half are left.
     */

    private fun tenAndAHalfSecondsInto(source: Voice): Float {
        PlaybackHost.startVoice(context, source)
        PlaybackHost.setSleepTimer(SleepAfter.Duration(20_000))
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(10_500))
        return source.volumes.last()
    }

    @Test
    fun `a voice fades across the last ten seconds`() {
        val gain = tenAndAHalfSecondsInto(voice)

        assertEquals(0.95f, gain, 0.01f)
    }

    @Test
    fun `a source that moves by seconds keeps the thirty-second fade`() {
        val narrated = Voice(SkipUnit.SECONDS)
        try {
            val gain = tenAndAHalfSecondsInto(narrated)

            assertEquals(9_500f / 30_000f, gain, 0.01f)
        } finally {
            PlaybackHost.stopVoice(narrated)
        }
    }
}
