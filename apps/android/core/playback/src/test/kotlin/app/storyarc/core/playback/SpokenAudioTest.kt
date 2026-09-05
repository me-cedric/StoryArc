package app.storyarc.core.playback

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Two engines, one answer to "may this source start".
 *
 * `audio-playback`, *Starting a second thing*:
 *
 * > **THEN** the first stops and its position is recorded before the second begins, because
 * > two books speaking at once is never what was meant
 * > **AND** the first is not resumed automatically when the second ends
 *
 * **This is the case Android could not answer.** The question was asked of one engine at a
 * time — `EpubReaderActivity` asked it of `ReadAloudHost` and `PlaybackHost.start` displaced
 * only what `PlaybackCentre` held — so a narrated audiobook and a spoken EPUB could speak
 * together. iOS cannot reach that state because read-aloud is already a second
 * `PlaybackSource` inside the one `PlayerCentre`; here the two engines are still two, and
 * [SpokenAudio] is what makes the rule true across them anyway.
 *
 * The cases below are the ones a device cannot easily produce: a voice starting under a
 * narrator, a narrator starting under a voice, and coming back to what is already speaking.
 * No engine, no `Context`, no service — the authority is a class for exactly that reason.
 */
class SpokenAudioTest {

    /**
     * A speaker with nothing behind it.
     *
     * Stands for both: what separates `PlaybackHost` from `ReadAloudHost`, as far as this
     * authority is concerned, is nothing at all — which is the point being asserted.
     */
    private class FakeSpeaker(
        private val name: String,
        private val log: MutableList<String>,
        var speakingNow: String? = null,
        /**
         * Whether the teardown takes effect inside the call.
         *
         * Both real speakers tear down synchronously today, and a speaker that does not is
         * the one case where being registered twice would ask it to stop twice — so the
         * de-duplication in [SpokenAudio.register] can only be asserted through one.
         */
        private val endsInstantly: Boolean = true,
    ) : SpokenAudio.Speaker {

        override val speaking: String? get() = speakingNow

        override fun endSpeaking() {
            log += "$name ended $speakingNow"
            if (endsInstantly) speakingNow = null
        }
    }

    private val log = mutableListOf<String>()

    private val narrator = FakeSpeaker("narrator", log)
    private val voice = FakeSpeaker("voice", log)

    private val audio = SpokenAudio().apply {
        register(narrator)
        register(voice)
    }

    @Test
    fun `nothing is speaking, so a publication opens silent and nothing is torn down`() {
        assertNull(audio.speaking)
        assertEquals(SessionHandover.NONE, audio.claim("sea-room", by = voice))
        assertEquals(emptyList<String>(), log)
    }

    /**
     * The defect, from the reader's side: a spoken session starting under a narrator.
     *
     * `ebook-reader` sends the reader here — read-aloud "SHALL drive the player" — and until
     * this authority existed the reader asked a question only the voice could answer, so the
     * narrator was never told.
     */
    @Test
    fun `a voice starting while a narrator plays displaces the narrator`() {
        narrator.speakingNow = "sea-room"

        assertEquals(SessionHandover.DISPLACE, audio.claim("the-peregrine", by = voice))

        assertEquals(listOf("narrator ended sea-room"), log)
        assertNull(audio.speaking)
    }

    /** And from the shelf's side: a narrated book starting under a voice. */
    @Test
    fun `a narrator starting while a voice speaks displaces the voice`() {
        voice.speakingNow = "the-peregrine"

        assertEquals(SessionHandover.DISPLACE, audio.claim("sea-room", by = narrator))

        assertEquals(listOf("voice ended the-peregrine"), log)
        assertNull(audio.speaking)
    }

    /**
     * Coming back to what is already being spoken picks it up rather than restarting it.
     *
     * `audio-playback` requires opening the player to "never restart, reload or reposition
     * the audio", and `ebook-reader` requires returning to resume "at the sentence being
     * spoken then". Both are the same answer: nothing is torn down.
     */
    @Test
    fun `coming back to the publication a speaker holds adopts it, and nothing stops`() {
        voice.speakingNow = "sea-room"

        assertEquals(SessionHandover.ADOPT, audio.claim("sea-room", by = voice))

        assertEquals(emptyList<String>(), log)
        assertEquals("sea-room", audio.speaking)
    }

    /**
     * A speaker cannot adopt another speaker's session.
     *
     * A reader has no cursor to pick up from a narrator and a narrator has no sentence to
     * hand a reader, so a shared identity is a displacement like any other. iOS reaches the
     * same guard from the other end: `prepareReadAloud` asks the player for the handover and
     * then re-checks that it is the *voice* holding the book before it adopts.
     */
    @Test
    fun `one speaker does not adopt what another is speaking`() {
        narrator.speakingNow = "sea-room"

        assertEquals(SessionHandover.DISPLACE, audio.claim("sea-room", by = voice))

        assertEquals(listOf("narrator ended sea-room"), log)
        assertNull(audio.speaking)
    }

    /**
     * And a speaker holding one book while another holds a second is never left half-ended.
     *
     * The state should not arise — it is what everything above exists to prevent — but the
     * arbiter is the last place that could leave it standing, so it is asserted rather than
     * assumed.
     */
    @Test
    fun `claiming while two are somehow speaking silences both`() {
        narrator.speakingNow = "sea-room"
        voice.speakingNow = "the-peregrine"

        assertEquals(SessionHandover.DISPLACE, audio.claim("the-peregrine", by = voice))

        assertEquals(listOf("narrator ended sea-room", "voice ended the-peregrine"), log)
        assertNull(audio.speaking)
    }

    /** A `begin` that always starts fresh ends whatever was speaking, without asking. */
    @Test
    fun `silencing ends every speaker, and asks a silent one for nothing`() {
        narrator.speakingNow = "sea-room"

        audio.silence()

        assertEquals(listOf("narrator ended sea-room"), log)
        assertNull(audio.speaking)
    }

    /**
     * Asked twice, registered once: a speaker cannot be told to stop two times over.
     *
     * The speaker below does not go silent inside its own teardown, which is the only shape
     * that can tell the two apart — and the shape any engine that ends asynchronously would
     * have. A duplicate registration is otherwise invisible right up to the day it is not.
     */
    @Test
    fun `registering the same speaker twice adds it once`() {
        val slow = FakeSpeaker("slow", log, speakingNow = "sea-room", endsInstantly = false)
        audio.register(slow)
        audio.register(slow)

        audio.silence()

        assertEquals(listOf("slow ended sea-room"), log)
    }

    /**
     * The narrated host answers this interface, and answers null when nothing plays.
     *
     * A typed assignment rather than a behaviour assertion, and it is the half a host test
     * can reach: `PlaybackHost` needs a `Context` and a bound service before it can speak.
     * What it pins is that the seam is connected on this side at all — the object the app
     * starts audiobooks through *is* a [SpokenAudio.Speaker], so a voice claiming the audio
     * has something to displace.
     *
     * **The dispatcher is set because touching the object builds its scope.** `PlaybackHost`
     * holds a `CoroutineScope` on `Dispatchers.Main.immediate` for the sleep timer's fade,
     * and a plain JVM test has no main looper for it to resolve — the failure is an
     * `ExceptionInInitializerError` from the assignment below and reads like nothing at all.
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `the narrated host is one of the speakers this authority arbitrates`() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        try {
            val speaker: SpokenAudio.Speaker = PlaybackHost
            assertNull(speaker.speaking)
        } finally {
            Dispatchers.resetMain()
        }
    }
}
