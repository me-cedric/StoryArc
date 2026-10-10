package app.storyarc.feature.epubreader

import android.content.Intent
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.os.Looper
import app.storyarc.core.playback.PauseCause
import app.storyarc.core.playback.PlaybackState
import kotlinx.coroutines.sync.Semaphore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAudioManager
import org.robolectric.shadows.ShadowTextToSpeech

/**
 * A call taken while the voice speaks, as the system sends it, to the real controller.
 *
 * Task 4.1. `PlaybackSessionTest` asserts the table: a call's end resumes, a listener's pause is
 * never undone, audio taken for good ends the session. Nothing connected that table to the
 * `AudioManager.OnAudioFocusChangeListener` [ReadAloudController] registers, so a mapping that
 * read `AUDIOFOCUS_GAIN` as `mayResume = false` would have passed every test in the module.
 * This raises each focus change the way the framework does, through the request the controller
 * made, and reads what the voice does and what it says.
 *
 * The text is a walk of three sentences instead of a Readium content service, and the engine
 * is Robolectric's `TextToSpeech`, which records what it is asked to say.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37; 34 is above the app's minimum.
@Config(sdk = [34])
class VoiceFocusTest {

    private val context = RuntimeEnvironment.getApplication()
    private val audio: ShadowAudioManager = shadowOf(context.getSystemService(AudioManager::class.java))
    private var voice: ReadAloudController? = null

    /**
     * Three sentences, and only the first is handed over freely.
     *
     * Robolectric's engine reports every utterance started and done the moment it is asked to
     * say it, so a walk that never waits runs to the end of the book inside the first press.
     * The gate holds the second sentence back, which leaves the voice mid-book, as a listener
     * finds it.
     */
    private class Walk(private val texts: List<String>) : SentenceWalk {
        private var next = 0
        private val gate = Semaphore(1)
        override fun restart(from: Locator?) { next = 0 }
        override fun restartAtResource(index: Int): Boolean = false
        override suspend fun next(): Sentence? {
            gate.acquire()
            return texts.getOrNull(next)?.let { text ->
                Sentence(
                    locator = Locator(href = Url("chapter-1.xhtml")!!, mediaType = MediaType.XHTML),
                    text = text,
                    language = null,
                ).also { next += 1 }
            }
        }
        override suspend fun previous(): Sentence? = null
    }

    @Before
    fun aVoiceOnAFreshDevice() {
        val publication = Publication(Manifest(metadata = Metadata(localizedTitle = LocalizedString("Harbour"))))
        voice = ReadAloudController(
            context = context,
            publication = publication,
            onSentence = {},
            sentences = Walk(listOf("One.", "Two.", "Three.")),
        )
    }

    @After
    fun quiet() {
        voice?.release()
        voice = null
    }

    private fun speaking(): ReadAloudController = requireNotNull(voice).also {
        it.start(null)
        // The platform reports the engine ready from a callback, and Robolectric leaves that to the test.
        engine().onInitListener.onInit(TextToSpeech.SUCCESS)
        settle { said() != null }
    }

    private fun engine(): ShadowTextToSpeech =
        shadowOf(requireNotNull(ShadowTextToSpeech.getLastTextToSpeechInstance()) { "no engine was built" })

    private fun said(): String? = ShadowTextToSpeech.getLastTextToSpeechInstance()?.let { engine().lastSpokenText }

    private fun focusChange(change: Int) {
        val request = requireNotNull(audio.lastAudioFocusRequest) { "the voice asked for no focus" }
        request.listener.onAudioFocusChange(change)
        shadowOf(Looper.getMainLooper()).idle()
    }

    /** Waits for the walk, which reads off the main thread, to reach the main looper again. */
    private fun settle(condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 5_000
        while (!condition() && System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
        assertTrue("the voice never reached the state the case needs", condition())
    }

    /** Lets a walk that would run, run: it reads off the main thread, so one idle is not enough. */
    private fun idleFor() {
        val deadline = System.currentTimeMillis() + 500
        while (System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
    }

    @Test
    fun `pressing play asks for the speaker and says the first sentence`() {
        val voice = speaking()

        assertEquals("One.", said())
        assertTrue(voice.session.value.isPlaying)
    }

    /** `ebook-reader`: "resumes … after a call, not after a listener pause". */
    @Test
    fun `a call pauses the voice and its end gives the speaker back`() {
        val voice = speaking()

        focusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        assertEquals(PlaybackState.PAUSED, voice.session.value.state)
        assertEquals(PauseCause.INTERRUPTION, voice.session.value.pausedBy)

        engine().clearLastSpokenText()
        focusChange(AudioManager.AUDIOFOCUS_GAIN)

        assertTrue("the call ended and the voice stayed silent", voice.session.value.isPlaying)
        assertEquals("the sentence that was cut off is said again, from its start", "One.", said())
    }

    @Test
    fun `a spoken direction that asks the voice to duck pauses it the same way`() {
        val voice = speaking()

        focusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)
        assertEquals(PauseCause.INTERRUPTION, voice.session.value.pausedBy)

        focusChange(AudioManager.AUDIOFOCUS_GAIN)
        assertTrue(voice.session.value.isPlaying)
    }

    @Test
    fun `a call after the listener paused leaves the voice silent`() {
        val voice = speaking()
        voice.toggle()
        assertEquals(PauseCause.LISTENER, voice.session.value.pausedBy)

        engine().clearLastSpokenText()
        focusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        focusChange(AudioManager.AUDIOFOCUS_GAIN)

        assertFalse("the call's end undid the listener's pause", voice.session.value.isPlaying)
        assertEquals(PauseCause.LISTENER, voice.session.value.pausedBy)
        assertNull("something was said after the listener paused", said())
    }

    /**
     * The call comes and goes before the engine has bound.
     *
     * A cold engine takes a few hundred milliseconds to bind. On the API 36 CI emulator the call
     * of `VoiceFocusInstrumentedTest` ended inside that time, the controller spoke to an engine
     * that was not bound, the engine refused, and the refusal stopped the session.
     */
    @Test
    fun `a call that ends while the engine binds resumes the voice once it is ready`() {
        val voice = requireNotNull(voice)
        voice.start(null)

        focusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        focusChange(AudioManager.AUDIOFOCUS_GAIN)
        idleFor()
        assertTrue("the call ended and the voice stayed silent", voice.session.value.isPlaying)
        assertNull("the voice spoke to an engine that was not ready", said())

        engine().onInitListener.onInit(TextToSpeech.SUCCESS)
        settle { said() != null }
        assertEquals("One.", said())
        assertTrue(voice.session.value.isPlaying)
    }

    @Test
    fun `a pause while the engine binds keeps the voice silent once it is ready`() {
        val voice = requireNotNull(voice)
        voice.start(null)
        voice.toggle()

        engine().onInitListener.onInit(TextToSpeech.SUCCESS)
        idleFor()

        assertEquals(PauseCause.LISTENER, voice.session.value.pausedBy)
        assertNull("something was said after the listener paused", said())
    }

    @Test
    fun `a call that begins after the listener paused and ends is not a resume`() {
        val voice = speaking()
        voice.toggle()
        focusChange(AudioManager.AUDIOFOCUS_GAIN)

        assertEquals(PlaybackState.PAUSED, voice.session.value.state)
    }

    @Test
    fun `speaker taken for good ends the session and gives the focus up`() {
        val voice = speaking()

        focusChange(AudioManager.AUDIOFOCUS_LOSS)

        assertFalse("the session was left paused for ever", voice.session.value.isActive)
        assertNotNull(audio.lastAbandonedAudioFocusRequest)
    }

    @Test
    fun `headphones pulled out pause the voice as the listener and nothing resumes it`() {
        val voice = speaking()

        context.sendBroadcast(Intent(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(PauseCause.LISTENER, voice.session.value.pausedBy)

        focusChange(AudioManager.AUDIOFOCUS_GAIN)
        assertFalse(voice.session.value.isPlaying)
    }
}
