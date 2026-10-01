package app.storyarc.feature.epubreader

import android.speech.tts.TextToSpeech
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What one utterance error means for the session, pulled out of [ReadAloudController] so the
 * rule is a plain JVM test rather than code only a real `TextToSpeech` service can exercise.
 *
 * `ebook-reader`, *The session cannot continue*: an engine that fails on every utterance used
 * to walk every sentence to the end of the book, writing each one's position, because the
 * only reply to an error was "try the next sentence". These assert the replacement: an
 * engine-level code ends the session at once, and a run of per-utterance ones ends it after
 * [MAX_CONSECUTIVE_SPEECH_ERRORS] rather than never.
 */
class ReadAloudSpeechErrorTest {

    @Test
    fun `one error naming a sentence does not end the session`() {
        assertFalse(shouldEndAfterSpeechError(TextToSpeech.ERROR_SYNTHESIS, consecutiveErrors = 1))
    }

    @Test
    fun `enough errors naming a sentence, in a row, end the session`() {
        assertTrue(
            shouldEndAfterSpeechError(
                TextToSpeech.ERROR_SYNTHESIS,
                consecutiveErrors = MAX_CONSECUTIVE_SPEECH_ERRORS,
            ),
        )
    }

    @Test
    fun `one error short of the count does not end the session`() {
        assertFalse(
            shouldEndAfterSpeechError(
                TextToSpeech.ERROR_SYNTHESIS,
                consecutiveErrors = MAX_CONSECUTIVE_SPEECH_ERRORS - 1,
            ),
        )
    }

    @Test
    fun `an engine-level error ends the session at once`() {
        assertTrue(shouldEndAfterSpeechError(TextToSpeech.ERROR_SERVICE, consecutiveErrors = 1))
    }

    /** One voice still downloading, for one quoted line, is not the whole engine failing. */
    @Test
    fun `one error for a voice still downloading does not end the session`() {
        assertFalse(
            shouldEndAfterSpeechError(TextToSpeech.ERROR_NOT_INSTALLED_YET, consecutiveErrors = 1),
        )
    }

    @Test
    fun `isEngineLevelSpeechError names the service, the output and the network, not synthesis`() {
        assertTrue(isEngineLevelSpeechError(TextToSpeech.ERROR_SERVICE))
        assertTrue(isEngineLevelSpeechError(TextToSpeech.ERROR_OUTPUT))
        assertTrue(isEngineLevelSpeechError(TextToSpeech.ERROR_NETWORK))
        assertTrue(isEngineLevelSpeechError(TextToSpeech.ERROR_NETWORK_TIMEOUT))
        assertFalse(isEngineLevelSpeechError(TextToSpeech.ERROR_NOT_INSTALLED_YET))
        assertFalse(isEngineLevelSpeechError(TextToSpeech.ERROR_SYNTHESIS))
        assertFalse(isEngineLevelSpeechError(TextToSpeech.ERROR_INVALID_REQUEST))
        assertFalse(isEngineLevelSpeechError(TextToSpeech.ERROR))
    }
}
