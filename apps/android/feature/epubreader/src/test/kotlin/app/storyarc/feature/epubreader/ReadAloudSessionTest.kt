package app.storyarc.feature.epubreader

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a pause means, and what ends it.
 *
 * A plain JVM test: this is the whole decision reading aloud makes, and the engine
 * around it is the platform's contract rather than this project's. iOS pins the same
 * cases in the same order in `ReadAloudSessionTests`.
 */
class ReadAloudSessionTest {

    private val idle = ReadAloudSession()
    private val speaking = idle.started()

    @Test
    fun `a session begins silent`() {
        assertEquals(ReadAloudState.IDLE, idle.state)
        assertFalse(idle.isSpeaking)
        assertFalse(idle.isActive)
    }

    @Test
    fun `starting speaks`() {
        assertEquals(ReadAloudState.SPEAKING, speaking.state)
        assertTrue(speaking.isSpeaking)
        assertNull(speaking.pausedBy)
    }

    @Test
    fun `a reader's pause is recorded as the reader's`() {
        val paused = speaking.pausedByReader()
        assertEquals(ReadAloudState.PAUSED, paused.state)
        assertEquals(PauseCause.READER, paused.pausedBy)
    }

    @Test
    fun `a paused session still offers its controls`() {
        assertTrue(speaking.pausedByReader().isActive)
        assertFalse(speaking.pausedByReader().isSpeaking)
    }

    @Test
    fun `the reader can start it again`() {
        assertEquals(ReadAloudState.SPEAKING, speaking.pausedByReader().resumed().state)
    }

    @Test
    fun `an interruption pauses and says so`() {
        val paused = speaking.interrupted()
        assertEquals(ReadAloudState.PAUSED, paused.state)
        assertEquals(PauseCause.INTERRUPTION, paused.pausedBy)
    }

    @Test
    fun `an interruption that ends well starts the voice again`() {
        val back = speaking.interrupted().interruptionEnded(mayResume = true)
        assertEquals(ReadAloudState.SPEAKING, back.state)
    }

    @Test
    fun `an interruption the platform will not resume leaves it paused`() {
        val still = speaking.interrupted().interruptionEnded(mayResume = false)
        assertEquals(ReadAloudState.PAUSED, still.state)
        assertEquals(PauseCause.INTERRUPTION, still.pausedBy)
    }

    /** The case this type exists for: a notification must not undo a deliberate pause. */
    @Test
    fun `an interruption never resumes a pause the reader made`() {
        val paused = speaking.pausedByReader()
        assertEquals(paused, paused.interrupted())
        assertEquals(paused, paused.interruptionEnded(mayResume = true))
    }

    @Test
    fun `audio taken for good stops it rather than holding it`() {
        assertEquals(ReadAloudState.IDLE, speaking.lostAudio().state)
        assertEquals(ReadAloudState.IDLE, speaking.interrupted().lostAudio().state)
    }

    @Test
    fun `nothing resumes a session that was never started`() {
        assertEquals(idle, idle.resumed())
        assertEquals(idle, idle.pausedByReader())
        assertEquals(idle, idle.interrupted())
    }

    @Test
    fun `stopping clears the cause with the state`() {
        val stopped = speaking.interrupted().stopped()
        assertEquals(ReadAloudState.IDLE, stopped.state)
        assertNull(stopped.pausedBy)
    }

    @Test
    fun `the lock screen names the chapter under the title`() {
        val label = SpokenLabel.of("Sea Room", "Chapter Two", "Adam Nicolson")
        assertEquals("Sea Room", label.title)
        assertEquals("Chapter Two", label.detail)
    }

    @Test
    fun `a book with no navigation falls back to its author`() {
        assertEquals("Adam Nicolson", SpokenLabel.of("Sea Room", null, "Adam Nicolson").detail)
        assertEquals("Adam Nicolson", SpokenLabel.of("Sea Room", "  ", "Adam Nicolson").detail)
    }

    @Test
    fun `a book with neither says only its title`() {
        assertNull(SpokenLabel.of("Sea Room", null, null).detail)
        assertNull(SpokenLabel.of("Sea Room", "", " ").detail)
    }

    // Audio taken, and audio taken for good.

    /**
     * The case that had no branch at all on iOS: the audio comes back but the platform says
     * the voice may not, and the session sat paused with nothing able to start it.
     */
    @Test
    fun `audio taken for good ends the session rather than leaving it paused`() {
        assertEquals(
            InterruptionOutcome.LOST,
            speaking.interrupted().endingInterruption(mayResume = false),
        )
    }

    @Test
    fun `audio given back starts an interruption's own pause again`() {
        assertEquals(
            InterruptionOutcome.RESUME,
            speaking.interrupted().endingInterruption(mayResume = true),
        )
    }

    /**
     * Both halves of the same sentence in `ebook-reader`: a reader's pause is never
     * *resumed* by an interruption ending, and audio taken for good still ends the session
     * — because a session nothing can start is the thing the spec forbids.
     */
    @Test
    fun `an interruption ending never restarts a pause the reader made`() {
        val paused = speaking.pausedByReader()
        assertEquals(InterruptionOutcome.NOTHING, paused.endingInterruption(mayResume = true))
        assertEquals(InterruptionOutcome.LOST, paused.endingInterruption(mayResume = false))
    }

    @Test
    fun `nothing happens to a session that was never running`() {
        assertEquals(InterruptionOutcome.NOTHING, idle.endingInterruption(mayResume = true))
        assertEquals(InterruptionOutcome.NOTHING, idle.endingInterruption(mayResume = false))
    }

    // One book at a time.

    @Test
    fun `opening a publication while nothing speaks starts silent`() {
        assertEquals(SessionHandover.NONE, SessionHandover.opening("sea-room", null))
    }

    /**
     * Closing the publication mid-sentence and coming back to it: the reader picks the
     * voice up rather than starting a second session on the same book.
     */
    @Test
    fun `reopening the book being spoken adopts the session`() {
        assertEquals(SessionHandover.ADOPT, SessionHandover.opening("sea-room", "sea-room"))
    }

    @Test
    fun `opening a different book displaces the voice`() {
        assertEquals(
            SessionHandover.DISPLACE,
            SessionHandover.opening("the-peregrine", "sea-room"),
        )
    }

    // Where the listening got to.

    private val sentence = """{"href":"/chapter-4.xhtml","type":"text/html"}"""
    private val identity = PublicationIdentity(normalizedPath = "/books/sea-room.epub")
    private val moment = 1_700_000_000_000L

    /**
     * The path that can lose an hour. What the session hands the progress store is the
     * sentence the voice reached, as an opaque locator — never a page number, which a
     * reflowable book does not have.
     */
    @Test
    fun `the reached position is recorded as the sentence, not as a page`() {
        val record = ReachedPosition(sentence, progression = 0.42).record(identity, moment)
        assertEquals(identity, record.identity)
        assertEquals(ReadingPosition.Reflowable(0.42, sentence), record.position)
        assertEquals(moment, record.updatedAtEpochMillis)
        assertFalse(record.isFinished)
    }

    /** The end of the publication is the end of the content, not a page count. */
    @Test
    fun `listening to the last sentence finishes the book`() {
        assertTrue(ReachedPosition(sentence, 1.0).record(identity, moment).isFinished)
        assertFalse(ReachedPosition(sentence, 0.9989).record(identity, moment).isFinished)
    }

    /**
     * A session the process is reclaimed under writes nothing more, so what was written on
     * the way has to stand on its own — and an empty locator would stand for nothing.
     */
    @Test
    fun `a sentence with no locator is not written over a good position`() {
        assertFalse(ReachedPosition("", progression = 0.42).isRecordable)
        assertTrue(ReachedPosition(sentence, progression = 0.0).isRecordable)
    }
}
