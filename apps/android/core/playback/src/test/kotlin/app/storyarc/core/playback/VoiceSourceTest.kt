package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * One player, whichever engine makes the sound.
 *
 * `audio-playback`, *One player for everything that speaks*:
 *
 * > every source of spoken audio — a narrated audiobook and the read-aloud voice alike —
 * > SHALL drive that one surface
 *
 * and *Both sources look the same*:
 *
 * > every control the player offers works, or is absent — none is present and refusing
 *
 * Task 13.2: the Android voice drove a surface of its own, so leaving the reader left the
 * listener with no compact bar, no chapter list, no speed and no sleep timer. What is
 * asserted here is the `:core:playback` half — that a source which is not a decoder reaches
 * the one surface, and that the surface carries the two facts a voice differs by. The voice
 * itself is `:feature:epubreader`'s, and `ReadAloudSource` is its implementation.
 *
 * Over a source with no engine in it, deliberately: `AudiobookSource` needs a media3 player
 * and the voice needs a speech engine and a Readium publication, and neither is the rule.
 */
class VoiceSourceTest {

    /** A source that speaks sentences: no clock, no durations, one sentence to a skip. */
    private class Voice(
        override val publicationId: String = "harbour-lights",
        override val title: String = "Harbour Lights",
        override val parts: List<PlaybackPart> = listOf(
            PlaybackPart("Chapter One"),
            PlaybackPart("Chapter Two"),
        ),
    ) : PlayerSource {

        override val skipUnit: SkipUnit = SkipUnit.SENTENCE

        var partIndex = 0
        override val position: PlaybackPosition get() = PlaybackPosition(partIndex, 0)

        var state = PlaybackSession()
        override val session: PlaybackSession get() = state

        override var speed: PlaybackSpeed = PlaybackSpeed.NORMAL
            private set

        override var onChange: (() -> Unit)? = null
        override var onInterruptionEnd: ((mayResume: Boolean) -> Unit)? = null

        var sentencesSkipped = 0
        var finishedTheSentence = false
        var gain: Float? = null

        override fun play() {
            state = state.started()
            onChange?.invoke()
        }

        override fun pause() {
            state = state.pausedByListener()
            onChange?.invoke()
        }

        override fun stop() {
            state = state.stopped()
            onChange?.invoke()
        }

        override fun seek(to: PlaybackPosition) {
            partIndex = to.partIndex
            onChange?.invoke()
        }

        override fun setSpeed(speed: PlaybackSpeed) {
            this.speed = speed
            onChange?.invoke()
        }

        override fun skip(direction: SkipDirection, byMillis: Long) {
            sentencesSkipped += 1
        }

        override fun stopAtSentenceEnd() {
            finishedTheSentence = true
        }

        override fun setVolume(gain: Float) {
            this.gain = gain
        }
    }

    private fun started() = Voice().also { it.play() }

    // MARK: - The one surface

    @Test
    fun `a voice the centre has taken is what every surface draws`() {
        val voice = started()
        val centre = PlaybackCentre()

        centre.attach(voice)

        assertEquals("harbour-lights", centre.nowPlaying?.publicationId)
        assertEquals("Chapter One", centre.nowPlaying?.chapter)
        assertTrue(centre.nowPlaying?.isPlaying == true)
    }

    @Test
    fun `the surface says a skip moves a sentence, so the control can state it`() {
        val voice = started()
        val centre = PlaybackCentre()

        centre.attach(voice)

        assertEquals(SkipUnit.SENTENCE, centre.nowPlaying?.skipUnit)
    }

    @Test
    fun `a narrated source says seconds without being asked`() {
        assertEquals(SkipUnit.SECONDS, Narrated().skipUnit)
    }

    @Test
    fun `no part states a length, so the scrub control is absent and no total is stated`() {
        val voice = started()
        val centre = PlaybackCentre()

        centre.attach(voice)
        val playing = requireNotNull(centre.nowPlaying)

        assertFalse(playing.isScrubbable)
        assertNull(playing.statedPartDurationMillis)
        assertNull(playing.statedTotalMillis)
    }

    @Test
    fun `end of chapter is refused rather than offered, because nothing measures a chapter`() {
        val voice = started()
        val centre = PlaybackCentre()
        centre.attach(voice)

        assertNull(SleepTimer.of(SleepAfter.EndOfChapter, centre.nowPlaying))
    }

    // MARK: - The transport

    @Test
    fun `a skip asks the source for one sentence, whatever interval the centre offers`() {
        val voice = started()
        val centre = PlaybackCentre()
        centre.attach(voice)

        centre.skip(SkipDirection.FORWARD)

        assertEquals(1, voice.sentencesSkipped)
    }

    @Test
    fun `choosing a chapter moves the source that holds the session`() {
        val voice = started()
        val centre = PlaybackCentre()
        centre.attach(voice)

        centre.seekToPart(1)

        assertEquals(1, voice.partIndex)
        assertEquals("Chapter Two", centre.nowPlaying?.chapter)
    }

    @Test
    fun `choosing a chapter writes where the listener chose to be`() {
        val recorded = mutableListOf<PlaybackPosition>()
        val voice = started()
        val centre = PlaybackCentre(record = { _, at -> recorded += at })
        centre.attach(voice)

        centre.seekToPart(1)

        // Every write, not only the last: a chapter chosen is `audio-playback`'s "a
        // listener deciding where they are", and whichever of the centre's moments catch it
        // — the crossing it publishes, and the choice itself — must agree on the place.
        assertEquals(listOf(PlaybackPosition(1, 0)), recorded.distinct())
    }

    @Test
    fun `a speed the listener chose reaches the source and the surface`() {
        val voice = started()
        val centre = PlaybackCentre()
        centre.attach(voice)

        centre.setSpeed(PlaybackSpeed.of(1.5))

        assertEquals(1.5, voice.speed.rate, 0.0)
        assertEquals(1.5, centre.nowPlaying?.speed?.rate ?: 0.0, 0.0)
    }

    // MARK: - The sleep timer

    @Test
    fun `the fade reaches whatever is making the sound`() {
        val voice = started()
        val centre = PlaybackCentre()
        centre.attach(voice)

        centre.setVolume(0.25f)

        assertEquals(0.25f, voice.gain)
    }

    @Test
    fun `the timer's ending lets the sentence finish rather than cutting it`() {
        val voice = started()
        val centre = PlaybackCentre()
        centre.attach(voice)

        centre.stopAtSentenceEnd()

        assertTrue(voice.finishedTheSentence)
    }

    @Test
    fun `a narrated source has no sentence to finish, so it pauses`() {
        val narrated = Narrated()
        val centre = PlaybackCentre()
        narrated.play()
        centre.attach(narrated)

        centre.stopAtSentenceEnd()

        assertFalse(narrated.session.isPlaying)
    }

    /** A source taking every default: the shape a decoder has. */
    private class Narrated : PlayerSource {
        override val publicationId = "sea-room"
        override val title = "Sea Room"
        override val parts = listOf(PlaybackPart("One", PlaybackDuration.Known(600_000)))
        override val position = PlaybackPosition(0, 0)
        var state = PlaybackSession()
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
}
