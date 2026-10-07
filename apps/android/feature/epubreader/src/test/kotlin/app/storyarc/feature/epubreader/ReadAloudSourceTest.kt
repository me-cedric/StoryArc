package app.storyarc.feature.epubreader

import android.content.Context
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SkipDirection
import app.storyarc.core.playback.SkipUnit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The voice, as the shared player's second source.
 *
 * Task 13.2. `audio-playback`, *Both sources look the same*: "the surface, the controls and
 * the lock-screen presentation are the same" whichever engine produced the sound, and
 * "every control the player offers works, or is absent — none is present and refusing".
 *
 * What is asserted is the translation this type is: a sentence's href into the part the
 * player marks, and the player's transport into the voice's. The speaking itself is
 * [ReadAloudController]'s and needs an engine, which is why the voice here has none.
 *
 * Robolectric for `Context` and `Locator`, which Readium parses through Android's own JSON.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReadAloudSourceTest {

    /** A voice with no engine, counting what the player asked of it. */
    private class Voice(playing: Boolean = true) : SpokenVoice {
        override val context: Context = RuntimeEnvironment.getApplication()
        private val _session = MutableStateFlow(
            if (playing) PlaybackSession().started() else PlaybackSession(),
        )
        override val session: StateFlow<PlaybackSession> = _session.asStateFlow()

        var toggles = 0
        var skippedForward = mutableListOf<Boolean>()
        var jumpedTo: Int? = null
        var rate: Double? = null
        var stoppedAtSentenceEnd = false
        var stops = 0

        override fun start(from: Locator?) = Unit

        override fun toggle() {
            toggles += 1
            _session.value =
                if (_session.value.isPlaying) _session.value.pausedByListener() else _session.value.started()
        }

        override fun skip(forward: Boolean) { skippedForward += forward }
        override fun stop() { stops += 1 }
        override fun release() = Unit
        override fun setSpeed(rate: Double) { this.rate = rate }
        override fun jumpTo(resourceIndex: Int) { jumpedTo = resourceIndex }
        override fun stopAtSentenceEnd() { stoppedAtSentenceEnd = true }

        var volume: Float? = null
        override fun setVolume(gain: Float) { volume = gain }
    }

    private val readingOrder = listOf("cover.xhtml", "ch1.xhtml", "ch2.xhtml")

    private fun book() = SpokenBook(
        id = "harbour-lights-01",
        location = "/books/harbour-lights-01.epub",
        title = "Harbour Lights 01",
        series = "Harbour Lights",
        author = null,
    )

    private fun source(voice: Voice, openingAt: Int = 0) = ReadAloudSource(
        voice = voice,
        book = book(),
        parts = readingOrder.map { PlaybackPart(title = "") },
        readingOrder = readingOrder,
        openingAt = openingAt,
    )

    // MARK: - What the surface reads

    @Test
    fun `a skip over a voice moves a sentence, and the surface says so`() {
        assertEquals(SkipUnit.SENTENCE, source(Voice()).skipUnit)
    }

    @Test
    fun `the session is the voice's, never a copy of it`() {
        val voice = Voice(playing = false)
        val source = source(voice)

        voice.toggle()

        assertTrue(source.session.isPlaying)
    }

    @Test
    fun `it opens at the resource the reader was in`() {
        assertEquals(PlaybackPosition(2, 0), source(Voice(), openingAt = 2).position)
    }

    @Test
    fun `a sentence in the next resource moves the mark`() {
        val source = source(Voice())

        source.reached("ch2.xhtml")

        assertEquals(2, source.position.partIndex)
    }

    @Test
    fun `a sentence's anchor is not part of the resource's identity`() {
        val source = source(Voice())

        source.reached("ch1.xhtml#paragraph-4")

        assertEquals(1, source.position.partIndex)
    }

    @Test
    fun `a sentence from outside the reading order leaves the mark where it was`() {
        val source = source(Voice(), openingAt = 1)

        source.reached("footnotes.xhtml")

        assertEquals(1, source.position.partIndex)
    }

    @Test
    fun `every change tells the player to read the source again`() {
        val source = source(Voice())
        var redraws = 0
        source.onChange = { redraws += 1 }

        source.reached("ch1.xhtml")
        source.refresh()

        assertEquals(2, redraws)
    }

    // MARK: - The transport

    @Test
    fun `play on a paused voice starts it`() {
        val voice = Voice(playing = false)

        source(voice).play()

        assertEquals(1, voice.toggles)
    }

    @Test
    fun `play on a voice already speaking is not a pause`() {
        val voice = Voice(playing = true)

        source(voice).play()

        assertEquals(0, voice.toggles)
        assertTrue(voice.session.value.isPlaying)
    }

    @Test
    fun `pause on a voice already silent leaves it silent`() {
        val voice = Voice(playing = false)

        source(voice).pause()

        assertEquals(0, voice.toggles)
        assertFalse(voice.session.value.isPlaying)
    }

    @Test
    fun `a skip asks for one sentence, whatever interval the centre offers`() {
        val voice = Voice()

        source(voice).skip(SkipDirection.BACK, byMillis = 15_000)

        assertEquals(listOf(false), voice.skippedForward)
    }

    @Test
    fun `choosing a chapter moves the walk and the mark together`() {
        val voice = Voice()
        val source = source(voice)

        source.seekToPart(2)

        assertEquals(2, voice.jumpedTo)
        assertEquals(2, source.position.partIndex)
    }

    @Test
    fun `a chapter the publication does not hold is refused rather than guessed at`() {
        val voice = Voice()
        val source = source(voice, openingAt = 1)

        source.seekToPart(9)

        assertNull(voice.jumpedTo)
        assertEquals(1, source.position.partIndex)
    }

    @Test
    fun `a speed the listener chose reaches the voice and is what the surface states`() {
        val voice = Voice()
        val source = source(voice)

        source.setSpeed(PlaybackSpeed.of(1.75))

        assertEquals(1.75, voice.rate ?: 0.0, 0.0)
        assertEquals(1.75, source.speed.rate, 0.0)
    }

    @Test
    fun `the sleep timer lets the sentence finish rather than cutting it off`() {
        val voice = Voice()

        source(voice).stopAtSentenceEnd()

        assertTrue(voice.stoppedAtSentenceEnd)
    }

    /** Task 13.6, D19: the sleep timer's fade reaches the voice rather than stopping here. */
    @Test
    fun `the sleep timer's fade reaches the voice`() {
        val voice = Voice()

        source(voice).setVolume(0.4f)

        assertEquals(0.4f, voice.volume ?: 1f, 0f)
    }
}
