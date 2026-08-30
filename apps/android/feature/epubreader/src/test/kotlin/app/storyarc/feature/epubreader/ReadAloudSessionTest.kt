package app.storyarc.feature.epubreader

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
}
