package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the conflict rules are actually consulted, and that a pull says what to do next.
 *
 * Mirrors iOS's `ProgressPullTests`, assertion for assertion.
 */
class ProgressPullTest {

    private fun progress(
        id: String,
        fraction: Double,
        finished: Boolean = false,
        synced: Double? = null,
    ) = ReadingProgress(
        identity = PublicationIdentity(contentDigest = id),
        position = ReadingPosition.Reflowable(fraction, "{}"),
        isFinished = finished,
        updatedAtEpochMillis = 0,
        syncedPosition = synced?.let { ReadingPosition.Reflowable(it, "{}") },
    )

    @Test
    fun `a publication the reader has never opened is taken as the server has it`() {
        val pull = ProgressPull.merging(listOf(progress("one", 0.4))) { null }

        assertEquals(1, pull.toSave.size)
        assertTrue(pull.toPush.isEmpty())
        assertTrue(pull.conflicts.isEmpty())
    }

    @Test
    fun `a server further ahead than an untouched local record is adopted quietly`() {
        val held = progress("one", 0.2, synced = 0.2)
        val pull = ProgressPull.merging(listOf(progress("one", 0.6))) { held }

        assertEquals(0.6, pull.toSave.first().position.fraction, 0.001)
        assertTrue(pull.conflicts.isEmpty())
    }

    @Test
    fun `a server behind the local record is pushed to, not adopted`() {
        val held = progress("one", 0.8, synced = 0.8)
        val pull = ProgressPull.merging(listOf(progress("one", 0.3))) { held }

        assertTrue(pull.toSave.isEmpty())
        assertEquals(0.8, pull.toPush.first().position.fraction, 0.001)
    }

    @Test
    fun `both moved since the last sync is a conflict, and the further one wins`() {
        // Last synced at 0.2; this device read on to 0.5, another to 0.9.
        val held = progress("one", 0.5, synced = 0.2)
        val pull = ProgressPull.merging(listOf(progress("one", 0.9))) { held }

        assertEquals(1, pull.conflicts.size)
        assertEquals(0.9, pull.toSave.first().position.fraction, 0.001)
        // What was set aside, so it can be offered back.
        assertEquals(0.5, pull.conflicts.first().discarded.fraction, 0.001)
    }

    @Test
    fun `a publication finished anywhere stays finished`() {
        val held = progress("one", 0.5, synced = 0.5)
        val pull = ProgressPull.merging(listOf(progress("one", 0.1, finished = true))) { held }

        assertTrue(pull.toSave.first().isFinished)
    }

    @Test
    fun `a local record finished is pushed rather than being undone by the server`() {
        val held = progress("one", 1.0, finished = true, synced = 1.0)
        val pull = ProgressPull.merging(listOf(progress("one", 0.3))) { held }

        assertTrue(pull.toSave.isEmpty())
        assertTrue(pull.toPush.first().isFinished)
    }

    @Test
    fun `a pull of many publications sorts each into the right pile`() {
        // Keyed on the identity's own stable id, which is what a store would key on -- the
        // digest is one component of an identity and not the identity itself.
        val held = listOf(progress("adopt", 0.1, synced = 0.1), progress("push", 0.9, synced = 0.9))
        val pull = ProgressPull.merging(
            listOf(progress("adopt", 0.5), progress("push", 0.2), progress("new", 0.3)),
        ) { wanted -> held.firstOrNull { it.identity.stableId == wanted.stableId } }

        assertEquals(2, pull.toSave.size)
        assertEquals(1, pull.toPush.size)
    }

    @Test
    fun `nothing reported is nothing to do`() {
        val pull = ProgressPull.merging(emptyList()) { null }

        assertTrue(pull.toSave.isEmpty() && pull.toPush.isEmpty() && pull.conflicts.isEmpty())
    }
}
