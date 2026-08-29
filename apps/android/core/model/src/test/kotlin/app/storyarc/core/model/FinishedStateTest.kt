package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The completion timestamp, and the one rule that makes it worth having.
 *
 * `reading-progress` asks for a publication to be "recorded finished with a completion
 * timestamp". The rule that carries the risk is not setting it — it is *not resetting* it:
 * reopening a finished publication writes a new position, and a timestamp that moved with
 * it would say the reader finished the book again every time they glanced at it.
 *
 * iOS's `FinishedStateTests` asserts the same table.
 */
class FinishedStateTest {

    private val identity = PublicationIdentity(normalizedPath = "/comics/bone.cbz")
    private val first = 1_000L
    private val later = 9_000L

    private fun partial() = ReadingProgress(
        identity = identity,
        position = ReadingPosition.Page(index = 4, total = 20),
        updatedAtEpochMillis = first,
    )

    @Test
    fun `finishing stamps the moment it was finished`() {
        val done = partial().finished(true, first)

        assertTrue(done.isFinished)
        assertEquals(first, done.finishedAtEpochMillis)
    }

    @Test
    fun `finishing again keeps the first completion`() {
        val reread = partial().finished(true, first).finished(true, later)

        // The reader opened it again. They did not finish it again.
        assertEquals(first, reread.finishedAtEpochMillis)
        assertEquals(later, reread.updatedAtEpochMillis)
    }

    @Test
    fun `unfinishing drops the completion, because there is no longer one to date`() {
        val reopened = partial().finished(true, first).finished(false, later)

        assertFalse(reopened.isFinished)
        assertNull(reopened.finishedAtEpochMillis)
        assertEquals(later, reopened.updatedAtEpochMillis)
    }

    @Test
    fun `a publication nobody finished has no completion`() {
        assertNull(partial().finishedAtEpochMillis)
    }
}
