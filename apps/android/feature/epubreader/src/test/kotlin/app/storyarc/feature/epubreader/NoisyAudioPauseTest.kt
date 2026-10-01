package app.storyarc.feature.epubreader

import android.content.Intent
import android.media.AudioManager
import android.os.Looper
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Headphones removed, over a plain [android.content.Context] rather than the whole of
 * [ReadAloudController].
 *
 * `audio-playback`, *Headphones removed*. [ReadAloudController] had no
 * `ACTION_AUDIO_BECOMING_NOISY` receiver at all, so pulling a wired or Bluetooth output kept
 * the voice speaking out loud through whatever took its place — a phone's own speaker, most
 * often. This asserts the piece that can be asserted without a `TextToSpeech` and a Readium
 * `Publication`: that the broadcast reaches [NoisyAudioPause] while it is registered, and not
 * before registration or after it is undone.
 *
 * Robolectric, because registering a receiver and sending a broadcast both need a real
 * `Context`. The main looper is paused by default, so [send] idles it after every broadcast —
 * without that a registered receiver is never actually called, and every assertion below
 * would read the count it started with.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37; 34 is above the app's minimum.
@Config(sdk = [34])
class NoisyAudioPauseTest {

    private val context = RuntimeEnvironment.getApplication()

    private fun send() {
        context.sendBroadcast(Intent(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun `the broadcast is ignored before registration`() {
        var calls = 0
        NoisyAudioPause(onNoisy = { calls += 1 })

        send()

        assertEquals(0, calls)
    }

    @Test
    fun `a registered pause answers the broadcast`() {
        var calls = 0
        val pause = NoisyAudioPause(onNoisy = { calls += 1 })
        pause.register(context)

        send()

        assertEquals(1, calls)
    }

    /** The session starting twice must not register the same receiver twice over. */
    @Test
    fun `registering twice still answers the broadcast once`() {
        var calls = 0
        val pause = NoisyAudioPause(onNoisy = { calls += 1 })
        pause.register(context)
        pause.register(context)

        send()

        assertEquals(1, calls)
    }

    @Test
    fun `an unregistered pause is deaf to the broadcast again`() {
        var calls = 0
        val pause = NoisyAudioPause(onNoisy = { calls += 1 })
        pause.register(context)
        pause.unregister(context)

        send()

        assertEquals(0, calls)
    }
}
