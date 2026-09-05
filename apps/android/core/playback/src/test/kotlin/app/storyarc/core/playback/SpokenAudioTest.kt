package app.storyarc.core.playback

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Two engines, one answer to "may this source start" — and one word owed when the answer
 * stopped a voice.
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
 * `ebook-reader`, *Opening a different publication*, adds the word: "the listener is told once
 * that the voice stopped, rather than discovering it by silence". The second half of this
 * suite pins where that word is armed — only here, only for a voice — the way iOS's
 * `PlayerDisplacementTests` pins its `PlayerCentre.displace()`. The sentence itself is not
 * asserted: `VoiceStoppedNoticeTest` owns the value and the surfaces own the drawing.
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
     * authority is concerned, is [kind] and nothing else — which is the point being asserted.
     * The title a notice would name is looked up from the id, so the tests read as ids.
     */
    private class FakeSpeaker(
        private val name: String,
        private val log: MutableList<String>,
        override val kind: SpokenAudio.Kind,
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

        override val speaking: SpokenAudio.Spoken?
            get() = speakingNow?.let { SpokenAudio.Spoken(it, TITLES[it] ?: it) }

        override fun endSpeaking() {
            log += "$name ended $speakingNow"
            if (endsInstantly) speakingNow = null
        }
    }

    private val log = mutableListOf<String>()

    private val narrator = FakeSpeaker("narrator", log, SpokenAudio.Kind.NARRATOR)
    private val voice = FakeSpeaker("voice", log, SpokenAudio.Kind.VOICE)

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
        val slow = FakeSpeaker(
            "slow",
            log,
            SpokenAudio.Kind.NARRATOR,
            speakingNow = "sea-room",
            endsInstantly = false,
        )
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
     * has something to displace — and that it says which kind it is, so a displacement can
     * tell a narrator from a voice.
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
            assertEquals(SpokenAudio.Kind.NARRATOR, speaker.kind)
        } finally {
            Dispatchers.resetMain()
        }
    }

    // MARK: the word a displacement owes

    @Test
    fun `nothing is owed while nothing has been displaced`() {
        voice.speakingNow = "the-peregrine"
        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
    }

    /** The shelf's seam: a narrated book starting under a voice tells the listener, by name. */
    @Test
    fun `displacing a voice owes a word naming the book that went quiet`() {
        voice.speakingNow = "the-peregrine"

        audio.claim("sea-room", by = narrator)

        assertTrue(audio.voiceStopped.value.isPending)
        assertEquals("The Peregrine", audio.voiceStopped.value.title)
    }

    /**
     * `audio-playback` calls the source "a fact about the file". A narrator that stops when
     * you open another book is an event a reader already understands.
     */
    @Test
    fun `displacing a narrator owes nothing`() {
        narrator.speakingNow = "sea-room"

        audio.claim("the-peregrine", by = voice)

        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
    }

    /** The reader's seam, reached through `ReadAloudHost.begin`, which silences by name. */
    @Test
    fun `a begin that silences a voice owes the word too`() {
        voice.speakingNow = "the-peregrine"

        audio.silence(toSpeak = "sea-room")

        assertEquals("The Peregrine", audio.voiceStopped.value.title)
    }

    /**
     * Restarting the publication already being spoken is a restart, not a displacement —
     * nothing went quiet that the listener is not looking at.
     */
    @Test
    fun `silencing to restart the same publication owes nothing`() {
        voice.speakingNow = "the-peregrine"

        audio.silence(toSpeak = "the-peregrine")

        assertEquals(listOf("voice ended the-peregrine"), log)
        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
    }

    @Test
    fun `adopting the running session owes nothing`() {
        voice.speakingNow = "the-peregrine"

        assertEquals(SessionHandover.ADOPT, audio.claim("the-peregrine", by = voice))

        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
    }

    /**
     * The listener's own stop, a book running out and audio the platform took all end inside
     * the host — `ReadAloudHost.end`, `PlaybackHost.stop` — and never pass through this
     * object. From here they are one shape: a speaker that went silent on its own.
     */
    @Test
    fun `a speaker that goes silent on its own owes nothing`() {
        voice.speakingNow = "the-peregrine"

        voice.speakingNow = null

        assertNull(audio.speaking)
        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
    }

    /**
     * The surface's half of *once*: what it takes, it spends. A second look — the same screen
     * redrawn, or a return to it — finds nothing.
     */
    @Test
    fun `taking the notice gives it once and leaves nothing for a second render`() {
        voice.speakingNow = "the-peregrine"
        audio.claim("sea-room", by = narrator)

        val shown = audio.takeVoiceStopped()

        assertEquals("The Peregrine", shown.title)
        assertEquals(VoiceStoppedNotice.NONE, audio.voiceStopped.value)
        assertEquals(VoiceStoppedNotice.NONE, audio.takeVoiceStopped())
    }

    /** One word per stopping, not one word ever. */
    @Test
    fun `a second displacement arms a second word`() {
        voice.speakingNow = "the-peregrine"
        audio.claim("sea-room", by = narrator)
        audio.takeVoiceStopped()

        voice.speakingNow = "sea-room"
        audio.claim("the-peregrine", by = narrator)

        assertEquals("Sea Room", audio.voiceStopped.value.title)
    }

    /**
     * A narrator displaced while a voice's word is still owed must not take that word away:
     * only a pending notice is ever written.
     */
    @Test
    fun `a narrator's displacement leaves an unshown voice's word standing`() {
        voice.speakingNow = "the-peregrine"
        audio.claim("sea-room", by = narrator)
        narrator.speakingNow = "sea-room"

        audio.claim("the-peregrine", by = voice)

        assertEquals("The Peregrine", audio.voiceStopped.value.title)
    }

    private companion object {
        val TITLES = mapOf("sea-room" to "Sea Room", "the-peregrine" to "The Peregrine")
    }
}
