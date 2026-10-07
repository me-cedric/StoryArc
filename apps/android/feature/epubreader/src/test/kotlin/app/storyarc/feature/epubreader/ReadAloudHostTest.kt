package app.storyarc.feature.epubreader

import android.content.ComponentName
import android.content.Context
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.PlaybackHost
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackService
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.SkipUnit
import app.storyarc.core.playback.SleepAfter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
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

        /** Where the host told this voice to begin. */
        var startedFrom: Locator? = null

        /** How the host asks to be told a sentence was said. */
        var said: (suspend (Sentence) -> Unit)? = null

        override fun start(from: Locator?) {
            starts += 1
            startedFrom = from
            if (canStart) _session.value = _session.value.started()
        }

        override fun toggle() = Unit
        override fun skip(forward: Boolean) = Unit

        /** What the shared player asked of this voice, for the rules that read them back. */
        var rate: Double = 1.0
        var jumpedTo: Int? = null
        var stoppedAtSentenceEnd = false

        override fun setSpeed(rate: Double) { this.rate = rate }
        override fun jumpTo(resourceIndex: Int) { jumpedTo = resourceIndex }
        override fun stopAtSentenceEnd() { stoppedAtSentenceEnd = true }
        override fun setVolume(gain: Float) = Unit

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

    /** A screen that keeps what it was asked to draw. */
    private class Page : SpokenSentenceFollower {
        val drawn = mutableListOf<Sentence>()

        override suspend fun drawSpokenSentence(sentence: Sentence) { drawn += sentence }
        override suspend fun withdrawSpokenHighlight() = Unit
    }

    private fun begin(
        voice: Voice,
        from: Locator? = null,
        drawnBy: SpokenSentenceFollower = nobodyDrawing,
    ) = ReadAloudHost.begin(
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
        from = from,
        drawnBy = drawnBy,
        parts = listOf(PlaybackPart(title = "The Harbour")),
    ) { said -> voice.also { it.said = said } }

    /** The host is a process-wide object; a session left running would be the next test's. */
    @After
    fun quiet() = ReadAloudHost.end()

    /**
     * No service binds in this JVM. A started voice binds a controller so the player's media
     * service runs, and Robolectric would otherwise connect it with no component name.
     */
    @Before
    fun noServiceToBind() {
        val context = RuntimeEnvironment.getApplication()
        shadowOf(context).declareComponentUnbindable(ComponentName(context, PlaybackService::class.java))
    }

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

    // MARK: - The one player

    /*
     * Task 13.2. `audio-playback`, *One player for everything that speaks*: "every source of
     * spoken audio -- a narrated audiobook and the read-aloud voice alike -- SHALL drive
     * that one surface". The Android voice used to drive a surface of its own, so a listener
     * who left the reader had no compact bar to come back through and no full player at all.
     *
     * What `PlaybackHost` does with the source once it has it is `PlaybackHostVoiceTest`'s.
     * These two are the handover: that the host gives the player a started voice, and takes
     * it back when the voice goes quiet.
     */

    @Test
    fun `a started voice is what the shared player draws`() {
        val voice = Voice()

        begin(voice)

        assertEquals("harbour-lights-01", PlaybackHost.nowPlaying.value?.publicationId)
        assertEquals(SkipUnit.SENTENCE, PlaybackHost.nowPlaying.value?.skipUnit)
    }

    @Test
    fun `a voice that could not start is never given to the player`() {
        begin(Voice(canStart = false))

        assertNull(PlaybackHost.nowPlaying.value)
    }

    @Test
    fun `the end of the voice is the end of the player's session`() {
        begin(Voice())

        ReadAloudHost.end()

        assertNull(PlaybackHost.nowPlaying.value)
    }

    /**
     * And the end is told to the player rather than noticed by it.
     *
     * The session this host gives up reaches the player twice: through the source's own
     * flow, and through the stop this host sends. Only the second ends the *player's*
     * session rather than the source's, and a sleep timer is what tells them apart -- it is
     * the host's, it outlives a source being let go, and a listener whose book has already
     * stopped must not have a timer still counting down on it.
     */
    @Test
    fun `a sleep timer does not outlive the voice it was counting down`() {
        begin(Voice())
        PlaybackHost.setSleepTimer(SleepAfter.Duration(15 * 60_000L))

        ReadAloudHost.end()

        assertNull(PlaybackHost.sleep.value)
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

    // MARK: - Starting playback

    /*
     * `ebook-reader`, *Starting playback*:
     *
     *   **THEN** speech begins at the current position, the spoken sentence is highlighted,
     *   and the page follows
     *
     * The three cases below are those three clauses. Until now the file asserted that the
     * host announced a started voice; where the voice was told to begin, and whether the
     * sentence it said ever reached the page, were asserted by nothing.
     *
     * The locator is a real Readium `Locator`. Robolectric supplies the `android.net.Uri`
     * that Readium's `Url` is built on — a plain JVM unit test gets the stub, which is the
     * reason `ReturnPointTest` is instrumented.
     */

    private fun sentence(href: String, title: String?, text: String) = Sentence(
        locator = Locator(
            href = requireNotNull(Url(href)),
            mediaType = MediaType.XHTML,
            title = title,
            locations = Locator.Locations(progression = 0.25, totalProgression = 0.4),
        ),
        text = text,
        language = null,
    )

    /**
     * Speech begins where the reader is, not at the top of the book.
     *
     * The locator `EpubReaderActivity` hands over is the navigator's own, so a listener who
     * presses *read aloud* on page two hundred is not read the first two hundred pages.
     */
    @Test
    fun `the voice begins at the position the reader was on`() {
        val voice = Voice()
        val here = sentence("/chapter-7.xhtml", "Chapter Seven", "The tide was out.").locator

        begin(voice, from = here)

        assertEquals(here, voice.startedFrom)
    }

    /** And a book nobody has opened yet begins at the beginning. */
    @Test
    fun `a book with no recorded position begins at its beginning`() {
        val voice = Voice()

        begin(voice, from = null)

        assertNull(voice.startedFrom)
    }

    /**
     * The sentence being spoken reaches the page, so the highlight and the page can follow.
     *
     * The host holds the screen weakly and feeds it from the callback it gave the voice.
     * Nothing asserted that the callback arrives anywhere: a host that dropped the sentence
     * would speak the whole book with the page standing still.
     */
    @Test
    fun `the sentence the voice says is drawn on the page`() {
        val voice = Voice()
        val page = Page()
        begin(voice, drawnBy = page)
        val said = requireNotNull(voice.said) { "the host gave the voice no way to report a sentence" }
        val spoken = sentence("/chapter-7.xhtml", "Chapter Seven", "The tide was out.")

        runBlocking { said(spoken) }

        assertEquals(listOf(spoken), page.drawn)
    }

    /**
     * And the transport's second line follows the voice across a chapter boundary.
     *
     * `ebook-reader`, *Background and lock screen*: "the second line names the chapter being
     * spoken". `SpokenLabel` decides how that line reads and `ReadAloudSessionTest` asserts
     * it; this asserts that the line is kept up to date while the voice walks.
     */
    @Test
    fun `the transport names the chapter the voice has reached`() {
        val voice = Voice()
        begin(voice)
        val said = requireNotNull(voice.said)

        runBlocking { said(sentence("/chapter-9.xhtml", "Chapter Nine", "Sea room.")) }

        assertEquals("Chapter Nine", ReadAloudHost.book.value?.label?.detail)
        // Task 13.2: the line the player's one media session gives the shade and lock screen.
        assertEquals("Chapter Nine", PlaybackHost.nowPlaying.value?.detail)
    }

    /**
     * Task 13.2: a tap on the notification goes back to the book being spoken, over the
     * library. `ebook-reader`: choosing the transport opens the publication "at the sentence
     * being spoken, without the voice stopping".
     */
    @Test
    fun `a tap on the notification goes back to the book being spoken`() {
        val context = RuntimeEnvironment.getApplication()
        val book = SpokenBook(
            id = "sea-room",
            location = "/books/sea-room.epub",
            title = "Sea Room",
            series = null,
            author = null,
        )

        val opened = shadowOf(requireNotNull(book.wayBack(context))).savedIntents.last()

        assertEquals(EpubReaderActivity::class.java.name, opened.component?.className)
        assertEquals(
            EpubReaderActivity.intent(context, book.location, book.title, book.series).extras?.keySet(),
            opened.extras?.keySet(),
        )
        assertTrue(opened.extras?.toString().orEmpty().contains("/books/sea-room.epub"))
    }

    // MARK: - Returning to the session

    /**
     * Task 6.2. `ebook-reader`: returning to a voice session resumes "at the sentence being
     * spoken then, not at the position from when they left, because the voice did not wait".
     *
     * The reader leaves, the voice says two more sentences with nobody drawing, and a new
     * reader adopts the session. The new reader draws the third sentence. It does not draw the
     * opening locator, and the reader that left draws nothing more.
     */
    @Test
    fun `a reader that adopts the session draws the sentence the voice is on`() {
        val voice = Voice()
        val opening = sentence("/chapter-1.xhtml", "Chapter One", "The tide was out.")
        val left = Page()
        begin(voice, from = opening.locator, drawnBy = left)
        val said = requireNotNull(voice.said)
        runBlocking { said(opening) }
        ReadAloudHost.release(left)
        val third = sentence("/chapter-3.xhtml", "Chapter Three", "Sea room.")

        runBlocking {
            said(sentence("/chapter-2.xhtml", "Chapter Two", "The boat lay on its side."))
            said(third)
        }
        val returned = Page()
        ReadAloudHost.adopt(returned)
        runBlocking { ReadAloudHost.redrawSpokenSentence() }

        assertEquals(listOf(third), returned.drawn)
        assertEquals("the reader that left was drawn on", listOf(opening), left.drawn)
    }
}
