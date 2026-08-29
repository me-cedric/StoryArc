package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Noticing what changed in a watched folder without re-reading it.
 *
 * `local-library`: a file added to a watched folder "appears in the library within 10 seconds
 * without a manual refresh", and a change made while the app was away is reconciled "by
 * comparing file modification times and sizes rather than re-reading every archive". iOS's
 * `FolderSnapshotTests` asserts the same cases against the same type.
 */
class FolderSnapshotTest {
    private fun entry(path: String, modified: Long = 1_000, size: Long = 10) =
        FolderSnapshot.Entry(path, modified, size)

    private fun snapshot(vararg entries: FolderSnapshot.Entry) =
        FolderSnapshot.of(entries.toList())

    @Test
    fun `a file that appeared is added`() {
        val change = requireNotNull(
            snapshot(entry("/a.cbz")).change(listOf(entry("/a.cbz"), entry("/b.cbz"))),
        )
        assertEquals(listOf("/b.cbz"), change.added.map { it.path })
        assertTrue(change.changed.isEmpty())
        assertTrue(change.removed.isEmpty())
    }

    @Test
    fun `a file that went is removed`() {
        val change = requireNotNull(
            snapshot(entry("/a.cbz"), entry("/b.cbz")).change(listOf(entry("/a.cbz"))),
        )
        assertEquals(listOf("/b.cbz"), change.removed)
        assertTrue(change.added.isEmpty())
    }

    @Test
    fun `a file is unchanged when neither its time nor its size moved`() {
        // The point of the comparison: this is what says which archives to skip.
        val change = requireNotNull(
            snapshot(entry("/a.cbz"), entry("/b.cbz"))
                .change(listOf(entry("/a.cbz"), entry("/b.cbz"))),
        )
        assertTrue(change.isEmpty)
        assertTrue(change.toIndex.isEmpty())
    }

    @Test
    fun `a file whose time moved is re-read`() {
        // A file replaced with one of the same length keeps its size, so the time has to
        // count on its own.
        val change = requireNotNull(
            snapshot(entry("/a.cbz")).change(listOf(entry("/a.cbz", modified = 2_000))),
        )
        assertEquals(listOf("/a.cbz"), change.changed.map { it.path })
    }

    @Test
    fun `a file whose size moved is re-read`() {
        // And a file restored from a backup keeps its time, so the size has to count too.
        val change = requireNotNull(
            snapshot(entry("/a.cbz")).change(listOf(entry("/a.cbz", size = 99))),
        )
        assertEquals(listOf("/a.cbz"), change.changed.map { it.path })
    }

    @Test
    fun `a walk that found nothing removes nothing`() {
        // Learnt on a device. A folder whose permission has gone stale, or a provider that
        // has not finished mounting, walks as empty -- and reading that as "the reader
        // deleted every book" empties their library.
        assertNull(snapshot(entry("/a.cbz"), entry("/b.cbz")).change(emptyList()))
    }

    @Test
    fun `a walk that found nothing does not overwrite a good snapshot`() {
        // The other half of the same guard. Throwing the snapshot away would make the pass
        // after the provider came back see every file as new and re-read the whole library.
        val kept = snapshot(entry("/a.cbz")).updated(emptyList())
        assertEquals(setOf("/a.cbz"), kept.entries.keys)
    }

    @Test
    fun `an empty folder that was always empty is not a refusal`() {
        // Nothing to protect: refusing here would mean a genuinely empty library never got
        // its first file.
        assertTrue(requireNotNull(FolderSnapshot().change(emptyList())).isEmpty)
    }

    @Test
    fun `a snapshot follows the walk it was updated to`() {
        val moved = snapshot(entry("/a.cbz")).updated(listOf(entry("/b.cbz")))
        assertEquals(setOf("/b.cbz"), moved.entries.keys)
    }

    @Test
    fun `what has to be opened is the added and the changed, and nothing else`() {
        val change = requireNotNull(
            snapshot(entry("/a.cbz"), entry("/b.cbz"), entry("/c.cbz")).change(
                listOf(entry("/a.cbz"), entry("/b.cbz", modified = 2_000), entry("/d.cbz")),
            ),
        )
        assertEquals(listOf("/b.cbz", "/d.cbz"), change.toIndex.map { it.path }.sorted())
        assertEquals(listOf("/c.cbz"), change.removed)
    }
}
