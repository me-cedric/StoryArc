package app.storyarc.feature.epubreader

import android.speech.tts.TextToSpeech
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 13.6, D19: the sleep timer fades a voice one sentence at a time, then stops it at the
 * end of the current sentence.
 *
 * iOS asserts the same rule in `SpokenSleepStopTests` and `SleepTimerRunningTests`. Robolectric
 * only for the `Bundle` that carries the volume to the engine.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SpokenVolumeTest {

    @Test
    fun `the next sentence is said at the volume the fade reached`() {
        val volume = SpokenVolume()

        volume.fade(to = 0.3f)

        assertEquals(0.3f, volume.gain, 0f)
    }

    /** The next sentence starts before the stop happens, and it must not start at full volume. */
    @Test
    fun `while the stop waits the volume stays where the fade left it`() {
        val volume = SpokenVolume()
        volume.fade(to = 0.1f)
        volume.stopAtSentenceEnd()

        volume.fade(to = 1f)

        assertEquals(0.1f, volume.gain, 0f)
    }

    @Test
    fun `the sentence that finishes ends the wait and gives back full volume`() {
        val volume = SpokenVolume()
        volume.fade(to = 0.1f)
        volume.stopAtSentenceEnd()

        assertTrue("the stop did not happen at the sentence end", volume.sentenceFinished())
        assertEquals(1f, volume.gain, 0f)
        assertFalse("a second sentence stopped too", volume.sentenceFinished())
    }

    /** A listener who presses play while the stop waits hears the book at full volume. */
    @Test
    fun `a listener who goes on ends the wait at full volume`() {
        val volume = SpokenVolume()
        volume.fade(to = 0.2f)
        volume.stopAtSentenceEnd()

        volume.goOn()

        assertFalse(volume.isStopping)
        assertEquals(1f, volume.gain, 0f)
    }

    /** Mid-fade with no stop waiting, the timer's next tick owns the volume. */
    @Test
    fun `going on mid-fade leaves the fade alone`() {
        val volume = SpokenVolume()
        volume.fade(to = 0.6f)

        volume.goOn()

        assertEquals(0.6f, volume.gain, 0f)
    }

    @Test
    fun `the engine is given the volume with the sentence`() {
        val params = speechParams(0.25f)

        assertEquals(0.25f, params.getFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME), 0f)
    }
}
