package app.storyarc.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two offline rules `collections-and-reading-lists` asks of a server-backed list: an
 * edit made while the server is away survives and is pushed, and an edit the server has
 * overtaken is discarded with one sentence about it.
 *
 * Mirrors iOS's `ShelfPullTests`, assertion for assertion.
 */
class ShelfPullTest {

    private val shelf = ShelfKey(sourceId = "server", shelfId = 7)

    private fun edit(entry: String, at: Long = 0) =
        ShelfEdit(shelf = shelf, entry = entry, title = "Entry $entry", madeAt = at)

    // The table

    @Test
    fun `nothing waiting settles nothing and says nothing`() {
        val outcome = ShelfMerge.merge(listOf("a"), listOf("a", "b"), emptyList())

        assertEquals(ShelfMergeOutcome.Settled(emptyList()), outcome)
    }

    @Test
    fun `a server that still holds what it held takes the outstanding edit`() {
        val queued = edit("b")
        val outcome = ShelfMerge.merge(listOf("a"), listOf("a"), listOf(queued))

        assertEquals(ShelfMergeOutcome.Push(listOf(queued)), outcome)
    }

    @Test
    fun `an edit the server already has is settled, not announced`() {
        val queued = edit("b")
        val outcome = ShelfMerge.merge(listOf("a"), listOf("a", "b"), listOf(queued))

        assertEquals(ShelfMergeOutcome.Settled(listOf(queued)), outcome)
    }

    @Test
    fun `a server that moved under an outstanding edit wins, and the edit is discarded`() {
        val queued = edit("b")
        val outcome = ShelfMerge.merge(listOf("a"), listOf("a", "c"), listOf(queued))

        assertEquals(ShelfMergeOutcome.Conflict(listOf(queued), emptyList()), outcome)
    }

    @Test
    fun `a reordered server is a conflict, because order is what a reading list is`() {
        val queued = edit("c")
        val outcome = ShelfMerge.merge(listOf("a", "b"), listOf("b", "a"), listOf(queued))

        assertEquals(ShelfMergeOutcome.Conflict(listOf(queued), emptyList()), outcome)
    }

    @Test
    fun `an edit that arrived before the server moved is settled, not discarded`() {
        val landed = edit("b", at = 1)
        val waiting = edit("d", at = 2)
        val outcome =
            ShelfMerge.merge(listOf("a"), listOf("a", "b", "c"), listOf(landed, waiting))

        assertEquals(ShelfMergeOutcome.Conflict(listOf(waiting), listOf(landed)), outcome)
    }

    @Test
    fun `a shelf never seen from this device is pushed to rather than second-guessed`() {
        val queued = edit("b")
        val outcome = ShelfMerge.merge(null, listOf("a", "c"), listOf(queued))

        assertEquals(ShelfMergeOutcome.Push(listOf(queued)), outcome)
    }

    // The projection

    @Test
    fun `a pending entry is on the list, after the server's own, and marked`() {
        val rows = ShelfMerge.projecting(
            remote = listOf(ShelfEntry("a", "First", isPending = false)),
            pending = listOf(edit("b", at = 2), edit("c", at = 1)),
        )

        assertEquals(listOf("a", "c", "b"), rows.map { it.id })
        assertEquals(listOf(false, true, true), rows.map { it.isPending })
    }

    @Test
    fun `an entry the server has already taken is not shown twice`() {
        val rows = ShelfMerge.projecting(
            remote = listOf(
                ShelfEntry("a", "First", isPending = false),
                ShelfEntry("b", "Second", isPending = false),
            ),
            pending = listOf(edit("b")),
        )

        assertEquals(listOf("a", "b"), rows.map { it.id })
        assertTrue(rows.none { it.isPending })
    }

    // The pull

    @Test
    fun `a shelf that did not answer keeps its edits and raises nothing`() {
        val pull = ShelfPull.merging(emptyList(), { listOf("a") }, listOf(edit("b")))

        assertTrue(pull.toPush.isEmpty())
        assertTrue(pull.toDrop.isEmpty())
        assertTrue(pull.conflicts.isEmpty())
    }

    @Test
    fun `two shelves are decided apart, and only the one that moved is announced`() {
        val other = ShelfKey(sourceId = "server", shelfId = 9)
        val quiet = edit("b")
        val clashing = ShelfEdit(shelf = other, entry = "z", title = "Entry z", madeAt = 0)

        val pull = ShelfPull.merging(
            remote = listOf(
                ShelfSnapshot(shelf, listOf("a")),
                ShelfSnapshot(other, listOf("a", "c")),
            ),
            baseline = { listOf("a") },
            pending = listOf(quiet, clashing),
        )

        assertEquals(listOf(quiet), pull.toPush)
        assertEquals(listOf(clashing), pull.toDrop)
        assertEquals(1, pull.conflicts.size)
        assertEquals(other, pull.conflicts.first().shelf)
        assertEquals(listOf(clashing), pull.conflicts.first().discarded)
    }

    // The queue

    @Test
    fun `the same entry queued twice is one pending edit`() {
        val queue = ShelfEditQueue().queueing(edit("b", at = 1)).queueing(edit("b", at = 2))

        assertEquals(1, queue.edits.size)
        assertEquals(2L, queue.edits.first().madeAt)
    }

    @Test
    fun `a baseline replaces the shelf's earlier one rather than joining it`() {
        val queue = ShelfEditQueue()
            .recording(ShelfSnapshot(shelf, listOf("a")))
            .recording(ShelfSnapshot(shelf, listOf("a", "b")))

        assertEquals(1, queue.baselines.size)
        assertEquals(listOf("a", "b"), queue.baseline(shelf))
    }

    @Test
    fun `a notice is told once - acknowledging it leaves nothing to tell`() {
        val notice = ShelfConflictNotice(shelf, "Crossover", listOf("Entry b"), at = 5)
        val queue = ShelfEditQueue().noting(notice)

        val first = requireNotNull(queue.nextNotice)
        assertEquals(listOf("Entry b"), first.discarded)
        assertNull(queue.acknowledging(first.id).nextNotice)
    }

    @Test
    fun `a queue survives being written and read back`() {
        val queue = ShelfEditQueue()
            .queueing(edit("b"))
            .recording(ShelfSnapshot(shelf, listOf("a")))
            .noting(ShelfConflictNotice(shelf, "Crossover", listOf("Entry c"), at = 5))

        val json = Json { ignoreUnknownKeys = true }
        assertEquals(queue, json.decodeFromString<ShelfEditQueue>(json.encodeToString(queue)))
    }

    @Test
    fun `a queue written before notices existed still reads`() {
        val json = Json { ignoreUnknownKeys = true }

        assertEquals(
            ShelfEditQueue(),
            json.decodeFromString<ShelfEditQueue>("""{"edits":[],"baselines":[]}"""),
        )
    }

    @Test
    fun `removing a source forgets its edits, its baselines and its notices`() {
        val queue = ShelfEditQueue()
            .queueing(edit("b"))
            .recording(ShelfSnapshot(shelf, listOf("a")))
            .noting(ShelfConflictNotice(shelf, "Crossover", listOf("Entry c"), at = 5))

        assertEquals(ShelfEditQueue(), queue.removingAll("server"))
    }
}
