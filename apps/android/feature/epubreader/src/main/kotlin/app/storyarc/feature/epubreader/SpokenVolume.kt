package app.storyarc.feature.epubreader

import android.os.Bundle
import android.speech.tts.TextToSpeech

/**
 * The voice's volume, and the sleep timer's stop that waits for the sentence end.
 *
 * D19: the sleep timer fades a voice in steps across the last ten seconds, then stops it at
 * the end of the current sentence. `TextToSpeech` applies a volume to the utterance it is
 * given, never to the one already speaking, so each sentence in the fade is a little quieter
 * than the one before.
 *
 * The two fields change together. While the stop waits, the volume stays where the fade left
 * it, so a sentence that starts in that time does not start at full volume. When the stop
 * happens, or the listener goes on, the voice gets its full volume back. iOS's `SpokenSource`
 * holds the same two fields with the same rule.
 *
 * Its own type, beside [ReadAloudController], so the rule is a JVM test rather than code that
 * needs a speech engine.
 */
internal class SpokenVolume {

    /** The volume the next sentence is said at, 0…1. */
    var gain: Float = 1f
        private set

    /** Whether a stop waits for the end of the sentence being said. */
    var isStopping: Boolean = false
        private set

    /** The sleep timer's fade. Ignored while a stop waits. */
    fun fade(to: Float) {
        if (isStopping) return
        gain = to.coerceIn(0f, 1f)
    }

    /** The sleep timer ran out: finish this sentence, then stop. */
    fun stopAtSentenceEnd() {
        isStopping = true
    }

    /**
     * The listener went on — a play, a pause, a skip, a chapter — so the stop no longer waits.
     *
     * Full volume again, but only when a stop was waiting. Mid-fade with no stop, the next
     * tick of the timer sets the volume, and this leaves it alone.
     */
    fun goOn() {
        if (!isStopping) return
        isStopping = false
        gain = 1f
    }

    /**
     * A sentence finished of its own accord.
     *
     * @return true when a stop was waiting for it, which ends the wait at full volume.
     */
    fun sentenceFinished(): Boolean {
        if (!isStopping) return false
        goOn()
        return true
    }
}

/** What [TextToSpeech.speak] is given for one sentence: its volume. */
internal fun speechParams(gain: Float): Bundle =
    Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, gain) }
