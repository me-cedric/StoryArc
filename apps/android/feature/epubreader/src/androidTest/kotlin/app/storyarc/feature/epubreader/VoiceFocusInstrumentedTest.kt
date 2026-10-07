package app.storyarc.feature.epubreader

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.playback.PauseCause
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.LocalizedString
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType

/**
 * A call taken while the voice speaks, on a device with a speech engine.
 *
 * Task 4.1. `VoiceFocusTest` raises each focus change on the host. This takes the speaker the
 * way another app does, with a second transient request from the same process, and gives it
 * back. A second request is a different client to the framework, so it takes the focus the
 * voice holds and the voice hears `AUDIOFOCUS_LOSS_TRANSIENT`, then `AUDIOFOCUS_GAIN`.
 *
 * Skipped where no engine starts: an emulator image without a speech service has no voice to
 * pause. The case says so, and names what it waited for.
 */
@RunWith(AndroidJUnit4::class)
class VoiceFocusInstrumentedTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context: Context get() = instrumentation.targetContext
    private val audio get() = context.getSystemService(AudioManager::class.java)
    private var voice: ReadAloudController? = null

    /** A long book of short sentences, so the voice is still mid-book when the case ends. */
    private class Walk : SentenceWalk {
        private var next = 0
        override fun restart(from: Locator?) { next = 0 }
        override fun restartAtResource(index: Int): Boolean = false
        override suspend fun next(): Sentence? =
            if (next >= SENTENCES) null else Sentence(
                locator = Locator(href = Url("chapter-1.xhtml")!!, mediaType = MediaType.XHTML),
                text = "Sentence number ${next++}.",
                language = null,
            )
        override suspend fun previous(): Sentence? = null
    }

    @After
    fun quiet() {
        instrumentation.runOnMainSync { voice?.release() }
        voice = null
    }

    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)

    private fun anotherApp(): AudioFocusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setOnAudioFocusChangeListener { }
            .build()

    private fun await(what: String, condition: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return true
            Thread.sleep(POLL_MILLIS)
        }
        System.err.println("VoiceFocusInstrumentedTest waited for: $what")
        return false
    }

    private fun speaking(): ReadAloudController {
        val publication = Publication(Manifest(metadata = Metadata(localizedTitle = LocalizedString("Harbour"))))
        val controller = ReadAloudController(context.applicationContext, publication, onSentence = {}, sentences = Walk())
        voice = controller
        onMain { controller.start(null) }
        Assume.assumeTrue(
            "No speech engine started on this device, so there is no voice to interrupt.",
            await("the voice to start speaking") { controller.session.value.isPlaying },
        )
        return controller
    }

    @Test
    fun aCallEndingResumesTheVoice() {
        val voice = speaking()
        val call = anotherApp()

        onMain { assertEquals(AudioManager.AUDIOFOCUS_REQUEST_GRANTED, audio.requestAudioFocus(call)) }
        assertTrue(
            "the voice kept speaking over the call",
            await("the voice to pause for the call") { voice.session.value.pausedBy == PauseCause.INTERRUPTION },
        )

        onMain { audio.abandonAudioFocusRequest(call) }
        assertTrue(
            "the call ended and the voice stayed silent",
            await("the voice to resume") { voice.session.value.isPlaying },
        )
    }

    @Test
    fun aCallEndingDoesNotUndoAListenersPause() {
        val voice = speaking()
        onMain { voice.toggle() }
        assertTrue(await("the listener's pause") { voice.session.value.pausedBy == PauseCause.LISTENER })
        val call = anotherApp()

        onMain { audio.requestAudioFocus(call) }
        onMain { audio.abandonAudioFocusRequest(call) }
        // Longer than the voice takes to answer a focus gain, which is well under a second.
        Thread.sleep(SILENCE_MILLIS)

        assertFalse("the call's end undid the listener's pause", voice.session.value.isPlaying)
        assertEquals(PauseCause.LISTENER, voice.session.value.pausedBy)
    }

    private companion object {
        const val SENTENCES = 400
        const val TIMEOUT_MILLIS = 15_000L
        const val POLL_MILLIS = 25L
        const val SILENCE_MILLIS = 2_500L
    }
}
