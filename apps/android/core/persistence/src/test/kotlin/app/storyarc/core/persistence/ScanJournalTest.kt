package app.storyarc.core.persistence

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.StreamingCapability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What an interrupted scan wrote down, and what a resumed one reads back.
 *
 * `local-library` requires a folder scan to be "cancellable and resumable". A scan of ten
 * thousand comics is minutes of opening archives, and a reader whose phone reclaimed the
 * process would otherwise watch the whole thing happen again from an empty grid. iOS's
 * `ScanJournalTests` asserts the same cases.
 */
class ScanJournalTest {
    private fun journal() = ScanJournal(FakePreferences())

    private fun publication(name: String, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$name.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = name,
        series = series,
        number = "1",
        authors = listOf("Jeff Smith"),
        origin = MetadataOrigin.EMBEDDED,
        pageCount = 24,
        coverPath = "001.png",
        readingDirection = ReadingDirection.RIGHT_TO_LEFT,
        streaming = StreamingCapability.DOWNLOAD_ONLY,
    )

    @Test
    fun `a folder nothing has scanned has nothing to resume`() {
        assertTrue(journal().indexed("/comics").isEmpty())
    }

    @Test
    fun `what a scan recorded comes back whole`() {
        // Whole, because the resumed scan puts these straight into the library rather than
        // re-reading them: anything lost here is a row that is wrong until the next scan.
        val journal = journal()
        journal.record(listOf(publication("Bone", series = "Bone")), "/comics")

        val read = journal.indexed("/comics").single()
        assertEquals("Bone", read.displayTitle)
        assertEquals("Bone", read.series)
        assertEquals("1", read.number)
        assertEquals(listOf("Jeff Smith"), read.authors)
        assertEquals(24, read.pageCount)
        assertEquals("001.png", read.coverPath)
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, read.readingDirection)
        assertEquals(StreamingCapability.DOWNLOAD_ONLY, read.streaming)
        assertEquals("/comics/Bone.cbz", read.identity.normalizedPath)
    }

    @Test
    fun `two folders keep their own journals`() {
        // A reader with two libraries can interrupt a scan of one of them, and the other must
        // not come back holding its files.
        val journal = journal()
        journal.record(listOf(publication("Bone")), "/comics")
        journal.record(listOf(publication("Maus"), publication("Persepolis")), "/books")

        assertEquals(1, journal.indexed("/comics").size)
        assertEquals(2, journal.indexed("/books").size)
    }

    @Test
    fun `a finished scan leaves nothing to resume`() {
        // Cleared rather than kept. This is a journal, not the metadata cache `sources` asks
        // for, and a journal that outlived its scan would be a stale library nobody decided
        // to keep.
        val journal = journal()
        journal.record(listOf(publication("Bone")), "/comics")
        journal.clear("/comics")
        assertTrue(journal.indexed("/comics").isEmpty())
    }

    @Test
    fun `clearing one folder leaves the others alone`() {
        val journal = journal()
        journal.record(listOf(publication("Bone")), "/comics")
        journal.record(listOf(publication("Maus")), "/books")
        journal.clear("/comics")
        assertEquals(1, journal.indexed("/books").size)
    }

    @Test
    fun `a later record replaces the earlier one rather than adding to it`() {
        // The writer holds the whole list anyway, and a store that could be half-written is
        // exactly the thing a resume must not read.
        val journal = journal()
        journal.record(listOf(publication("Bone")), "/comics")
        journal.record(listOf(publication("Bone"), publication("Maus")), "/comics")
        assertEquals(
            listOf("Bone", "Maus"),
            journal.indexed("/comics").map { it.displayTitle },
        )
    }
}
