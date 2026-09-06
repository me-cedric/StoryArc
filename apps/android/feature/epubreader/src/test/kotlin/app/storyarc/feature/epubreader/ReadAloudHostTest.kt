package app.storyarc.feature.epubreader

import android.content.Context
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.PlaybackSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * A voice that was started is the book being spoken, and one that could not start is let go.
 *
 * `ebook-reader`: pressing *read aloud* starts a session that "SHALL outlive the screen it was
 * started from", and the app's one authority displaces it when another publication opens — which
 * is only possible if [ReadAloudHost.speaking] names the book while the voice runs. Until
 * 2026-09-06 it did not, on any device, and nothing in this module could have said so: the host
 * watched its controller's session before it started the controller, the `StateFlow` handed the
 * watcher the idle session the controller was born with, and the watcher read idle as *ended*
 * and tore the voice down inside `begin` itself. The engine then bound and never spoke; the word
 * a displaced voice owes never showed, because there was never a voice to displace.
 *
 * Over a [SpokenVoice] with no engine, because the real one needs a Readium `Publication` and
 * a `TextToSpeech`. What is asserted is the host's own rule — what it does with a voice that
 * started, and with one that did not — which is exactly the part that was wrong.
 *
 * Robolectric, because a started voice is announced through a foreground service and `Intent`
 * is a stub in the plain unit-test JVM. The host's scope is `Dispatchers.Main.immediate`, which
 * Robolectric's main looper supplies; the ordering under test is what that dispatcher does with
 * a `StateFlow`'s current value, so the test has to run on it and not on a test dispatcher.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37; 34 is above the app's minimum.
@Config(sdk = [34])
class ReadAloudHostTest {

    /** A voice that starts when asked — or cannot — and counts what the host did to it. */
    private class Voice(private val canStart: Boolean = true) : SpokenVoice {
        override val context: Context = RuntimeEnvironment.getApplication()
        private val _session = MutableStateFlow(PlaybackSession())
        override val session: StateFlow<PlaybackSession> = _session.asStateFlow()
        var starts = 0
        var releases = 0

        override fun start(from: Locator?) {
            starts += 1
            if (canStart) _session.value = _session.value.started()
        }

        override fun toggle() = Unit
        override fun skip(forward: Boolean) = Unit

        override fun stop() {
            _session.value = _session.value.stopped()
        }

        override fun release() {
            releases += 1
            stop()
        }
    }

    private val nobodyDrawing = object : SpokenSentenceFollower {
        override suspend fun drawSpokenSentence(sentence: Sentence) = Unit
        override suspend fun withdrawSpokenHighlight() = Unit
    }

    private fun begin(voice: Voice) = ReadAloudHost.begin(
        book = SpokenBook(
            id = "harbour-lights-01",
            location = "/books/harbour-lights-01.epub",
            title = "Harbour Lights 01",
            series = "Harbour Lights",
            author = null,
        ),
        position = SpokenPosition(
            identity = PublicationIdentity(normalizedPath = "/books/harbour-lights-01.epub"),
            readingOrder = emptyList(),
            store = null,
        ),
        from = null,
        drawnBy = nobodyDrawing,
    ) { voice }

    /** The host is a process-wide object; a session left running would be the next test's. */
    @After
    fun quiet() = ReadAloudHost.end()

    /**
     * The defect, from the listener's side: the voice was started, so the host says so.
     *
     * Before the fix the second and third assertions failed and `releases` was 1 — the voice
     * had been released before it was started, and `starts` was still 1 because starting a
     * released voice is a call nothing refuses.
     */
    @Test
    fun `a voice that started is the book being spoken`() {
        val voice = Voice()

        begin(voice)

        assertEquals(1, voice.starts)
        assertEquals("harbour-lights-01", ReadAloudHost.speaking?.id)
        assertEquals("Harbour Lights 01", ReadAloudHost.book.value?.title)
        assertTrue("the host does not say the voice is playing", ReadAloudHost.session.value.isPlaying)
        assertEquals("the voice was released while it was speaking", 0, voice.releases)
    }

    /**
     * The one case where tearing down at once is right, and the reason the fix is an order
     * rather than a dropped first value: a voice that could not start — no speakable content,
     * no audio focus — leaves its session idle, and the host must not keep a book nobody is
     * reading. Skipping the flow's first value would have kept it.
     */
    @Test
    fun `a voice that could not start is let go at once`() {
        val voice = Voice(canStart = false)

        begin(voice)

        assertEquals(1, voice.starts)
        assertNull(ReadAloudHost.speaking)
        assertNull(ReadAloudHost.book.value)
        assertEquals(1, voice.releases)
    }

    /** And the listener's own stop is still the end of it. */
    @Test
    fun `the listener's stop ends the session and releases the voice`() {
        val voice = Voice()
        begin(voice)

        ReadAloudHost.end()

        assertNull(ReadAloudHost.speaking)
        assertEquals(1, voice.releases)
        assertTrue(!ReadAloudHost.session.value.isActive)
    }
}
