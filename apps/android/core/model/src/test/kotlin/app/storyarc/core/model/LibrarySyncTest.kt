package app.storyarc.core.model

import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` tasks 3.1, 3.6 and 3.7: read-merge-write, a provider's conflicted copy, and no
 * Kavita position in the document. iOS's `LibrarySyncTests` makes the same claims.
 */
class LibrarySyncTest {

    private val book = PublicationIdentity(contentDigest = "d1")
    private val other = PublicationIdentity(contentDigest = "d2")
    private val shelfA = UUID.fromString("aaaaaaaa-0000-0000-0000-000000000001")
    private val shelfB = UUID.fromString("bbbbbbbb-0000-0000-0000-000000000002")

    private fun collection(id: UUID, name: String, at: Long) =
        PublicationCollection(id = id, name = name, members = setOf("m:$name"), changedAtEpochMillis = at)

    @Test
    fun `two devices that write in turn both keep every record`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", LibrarySnapshot(shelves = Shelves(listOf(collection(shelfA, "A", moment(1))))))
        val b = SyncDevice("device-b", LibrarySnapshot(shelves = Shelves(listOf(collection(shelfB, "B", moment(2))))))
        b.read(book, page = 7, at = moment(3))

        a.sync(place, moment(10))
        b.sync(place, moment(11))
        a.sync(place, moment(12))

        for (device in listOf(a, b)) {
            assertEquals(setOf(shelfA, shelfB), device.library.shelves.collections.map { it.id }.toSet())
            assertEquals(ReadingPosition.Page(7, 100), device.position(book)?.position)
        }
        assertEquals(2, place.document().library.collections.size)
    }

    @Test
    fun `a write that finds the document changed reads it again and merges`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", LibrarySnapshot(shelves = Shelves(listOf(collection(shelfA, "A", moment(1))))))
        val b = SyncDevice("device-b", LibrarySnapshot(shelves = Shelves(listOf(collection(shelfB, "B", moment(2))))))
        // B writes between A's read and A's write.
        place.beforeWrite = { b.sync(place, moment(5)) }

        val outcome = a.sync(place, moment(6))

        assertTrue(outcome is LibrarySyncOutcome.Synced)
        assertEquals(2, place.writes)
        assertEquals(setOf(shelfA.toString(), shelfB.toString()), place.document().library.collections.map { it.id }.toSet())
        assertEquals(setOf(shelfA, shelfB), a.library.shelves.collections.map { it.id }.toSet())
    }

    @Test
    fun `a document that changes under every attempt is left alone`() = runTest {
        val place = MemoryPlace()
        place.put(LibrarySync.FILE_NAME, LibraryDocumentCoder.encode(LibraryExport.document(LibrarySnapshot(), "1.0", moment(0))))
        lateinit var rewrite: suspend () -> Unit
        rewrite = {
            place.put(LibrarySync.FILE_NAME, place.files.getValue(LibrarySync.FILE_NAME).text)
            place.beforeWrite = rewrite
        }
        place.beforeWrite = rewrite

        assertEquals(LibrarySyncOutcome.Busy, SyncDevice("device-a").sync(place, moment(1)))
        assertEquals(0, place.writes)
    }

    @Test
    fun `each record names the device and the moment of its last change`() = runTest {
        val place = MemoryPlace()
        val a = SyncDevice("device-a", LibrarySnapshot(shelves = Shelves(listOf(collection(shelfA, "A", moment(1))))))
        a.read(book, page = 3, at = moment(2))
        val b = SyncDevice("device-b")
        b.read(other, page = 9, at = moment(4))

        a.sync(place, moment(10))
        b.sync(place, moment(11))

        val written = place.document().library
        val shelf = written.collections.single()
        assertEquals("device-a", shelf.changedBy)
        assertEquals(wireMoment(moment(1)), shelf.changedAt)
        val byIdentity = written.progress.associate { it.identity.contentDigest to it.changedBy }
        assertEquals(mapOf("d1" to "device-a", "d2" to "device-b"), byIdentity)
    }

    @Test
    fun `a document written before sync existed still reads and merges`() = runTest {
        val place = MemoryPlace()
        place.put(LibrarySync.FILE_NAME, LibraryDocumentFixture.document("written-by-ios.json"))

        val device = SyncDevice("device-a")
        val outcome = device.sync(place, moment(1))

        assertTrue(outcome is LibrarySyncOutcome.Synced)
        assertEquals(listOf("Image Comics"), device.library.shelves.collections.map { it.name })
        assertEquals("Crossover", place.document().library.readingLists.single().name)
    }

    @Test
    fun `a newer document is refused by name and left as it was`() = runTest {
        val place = MemoryPlace()
        val newer = """{"formatVersion": 99}"""
        place.put(LibrarySync.FILE_NAME, newer)

        val outcome = SyncDevice("device-a").sync(place, moment(1))

        assertEquals(
            LibrarySyncOutcome.Refused(LibraryDocumentFailure.NewerThanThisApp(99, LibraryDocument.CURRENT_FORMAT_VERSION)),
            outcome,
        )
        assertEquals(newer, place.files.getValue(LibrarySync.FILE_NAME).text)
    }

    // 3.6: a provider's conflicted copy.

    @Test
    fun `each provider's name for a conflicted copy is recognised`() {
        val copies = listOf(
            "StoryArc Library 2.json",
            "StoryArc Library (1).json",
            "StoryArc Library (Reader's conflicted copy 2026-10-08).json",
            "StoryArc Library-PIXEL8.json",
        )
        copies.forEach { assertTrue(it, LibrarySync.isConflictedCopy(it)) }
        listOf("StoryArc Library.json", "Other.json", "StoryArc Library.json.bak", "StoryArc Library2.json")
            .forEach { assertTrue(it, !LibrarySync.isConflictedCopy(it)) }
    }

    private fun copyOf(snapshot: LibrarySnapshot, by: String): String =
        LibraryDocumentCoder.encode(LibraryExport.syncDocument(snapshot, "1.0", moment(20), by, null))

    @Test
    fun `a conflicted copy with a further position is merged and then deleted`() = runTest {
        val place = MemoryPlace()
        val device = SyncDevice("device-a")
        device.read(book, page = 10, at = moment(1))
        device.sync(place, moment(2))
        val further = LibrarySnapshot(
            progress = listOf(ReadingProgress(book, ReadingPosition.Page(50, 100), updatedAtEpochMillis = moment(3))),
        )
        place.put("StoryArc Library 2.json", copyOf(further, "device-b"))

        val outcome = device.sync(place, moment(4)) as LibrarySyncOutcome.Synced

        assertEquals(listOf("StoryArc Library 2.json"), outcome.copiesMergedNow)
        assertEquals(ReadingPosition.Page(50, 100), device.position(book)?.position)
        assertEquals(
            DocumentPosition(ReadingPosition.Page(50, 100)),
            place.document().library.progress.single().position,
        )
        assertNull(place.files["StoryArc Library 2.json"])
    }

    @Test
    fun `a corrupt conflicted copy is skipped and named`() = runTest {
        val place = MemoryPlace()
        place.put("StoryArc Library (1).json", "{ not a library")

        val outcome = SyncDevice("device-a").sync(place, moment(1)) as LibrarySyncOutcome.Synced

        assertEquals(listOf("StoryArc Library (1).json"), outcome.skippedCopies)
        assertEquals(emptyList<String>(), outcome.copiesMergedNow)
        assertTrue("StoryArc Library (1).json" in place.files)
    }

    @Test
    fun `a conflicted copy that cannot be deleted is not merged twice`() = runTest {
        val place = MemoryPlace()
        val device = SyncDevice("device-a")
        place.put("StoryArc Library 2.json", copyOf(LibrarySnapshot(shelves = Shelves(listOf(collection(shelfB, "B", moment(1))))), "device-b"))
        place.undeletable += "StoryArc Library 2.json"

        val first = device.sync(place, moment(2)) as LibrarySyncOutcome.Synced
        val second = device.sync(place, moment(3)) as LibrarySyncOutcome.Synced

        assertEquals(listOf("StoryArc Library 2.json"), first.copiesMergedNow)
        assertEquals(emptyList<String>(), second.copiesMergedNow)
        assertEquals(first.mergedCopies, second.mergedCopies)
    }

    // 3.7: Kavita keeps what Kavita owns.

    private val kavita = UUID.fromString("55555555-5555-5555-5555-555555555555")

    private fun kavitaLibrary(): LibrarySnapshot {
        val served = PublicationIdentity(serverIdentifier = PublicationIdentity.ServerIdentifier(kavita, "chapter:9"))
        val kept = PublicationIdentity(normalizedPath = "/kept/chapter-9.cbz")
        return LibrarySnapshot(
            sources = SourceRegistry(listOf(Source(id = kavita, displayName = "Kavita", kind = SourceKind.KAVITA_SERVER))),
            progress = listOf(
                ReadingProgress(served, ReadingPosition.Page(4, 20), updatedAtEpochMillis = moment(1)),
                ReadingProgress(kept, ReadingPosition.Page(5, 20), updatedAtEpochMillis = moment(1)),
                ReadingProgress(book, ReadingPosition.Page(6, 20), updatedAtEpochMillis = moment(1)),
            ),
            kavitaKept = setOf(kept.stableId),
        )
    }

    @Test
    fun `a sync document carries no Kavita position`() = runTest {
        val place = MemoryPlace()
        SyncDevice("device-a", kavitaLibrary()).sync(place, moment(2))

        val carried = place.document().library.progress.map { it.identity }
        assertEquals(listOf(DocumentIdentity(book)), carried)
    }

    @Test
    fun `a Kavita position is neither taken from the document nor stamped`() = runTest {
        val place = MemoryPlace()
        val library = kavitaLibrary()
        // A document from before the rule, which still carries a Kavita position further on.
        val old = library.copy(progress = library.progress.map { it.copy(position = ReadingPosition.Page(19, 20)) })
        place.put(LibrarySync.FILE_NAME, LibraryDocumentCoder.encode(LibraryExport.document(old, "1.0", moment(1))))
        val device = SyncDevice("device-a", library)

        device.sync(place, moment(2))

        val served = device.library.progress.first { it.identity.serverIdentifier != null }
        assertEquals(ReadingPosition.Page(4, 20), served.position)
        assertNull(served.syncedPosition)
    }
}
