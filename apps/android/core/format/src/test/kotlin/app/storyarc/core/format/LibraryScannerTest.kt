package app.storyarc.core.format

import app.storyarc.core.model.PublicationFormat
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * The scan is asserted against the real corpus directory, which is exactly the
 * mixed folder a user would point at: several formats, a damaged file, a refused
 * one, and an EPUB among the comics. iOS's `LibraryScannerTests` asserts the same.
 */
class LibraryScannerTest {
    @get:Rule
    val temp = TemporaryFolder()

    private val corpus: File get() = FixtureCorpus.root

    @Test
    fun `a folder of mixed formats yields a publication for each`() = runTest {
        val formats = LibraryScanner.scanAll(corpus).map { it.format }.toSet()
        // Comics, an ebook and a PDF all come out of one walk. A scan that only
        // finds one family is the common way this goes wrong.
        assertTrue(PublicationFormat.CBZ in formats)
        assertTrue(PublicationFormat.CBT in formats)
        assertTrue(PublicationFormat.CBR in formats)
        assertTrue(PublicationFormat.PDF in formats)
        assertTrue(PublicationFormat.EPUB in formats)
    }

    @Test
    fun `subdirectories are walked`() = runTest {
        // The corpus keeps comics and ebooks in sibling folders, so finding both
        // proves the walk descended rather than reading only the top level.
        val publications = LibraryScanner.scanAll(corpus)
        assertTrue(publications.any { it.format == PublicationFormat.EPUB })
        assertTrue(publications.any { it.format == PublicationFormat.CBZ })
    }

    @Test
    fun `a scan finishes with counts that match what it emitted`() = runTest {
        val events = LibraryScanner.scan(corpus).toList()
        val found = events.count { it is ScanEvent.Found }
        val skipped = events.count { it is ScanEvent.Skipped }

        val finished = events.last() as ScanEvent.Finished
        // A progress count that disagrees with the rows on screen is worse than no
        // count at all.
        assertEquals(found, finished.found)
        assertEquals(skipped, finished.skipped)
    }

    @Test
    fun `publications are emitted before the scan finishes`() = runTest {
        // `local-library` requires browsing what is already found while the scan
        // continues, which is only possible if rows arrive before the end.
        var sawPublicationBeforeFinish = false
        for (event in LibraryScanner.scan(corpus).toList()) {
            if (event is ScanEvent.Finished) break
            if (event is ScanEvent.Found) sawPublicationBeforeFinish = true
        }
        assertTrue(sawPublicationBeforeFinish)
    }

    @Test
    fun `an unreadable file is skipped with a reason, not dropped silently`() = runTest {
        val skips = LibraryScanner.scan(corpus).toList().filterIsInstance<ScanEvent.Skipped>()
        // refused.cb7 is in the corpus and must be reported by name.
        val sevenZip = skips.firstOrNull { it.path == "refused.cb7" }
        assertTrue("refused.cb7 was not reported", sevenZip != null)
        assertTrue(sevenZip!!.reason.contains("CB7"))
        assertTrue(skips.all { it.reason.isNotEmpty() })
    }

    @Test
    fun `a refused publication is found rather than skipped`() = runTest {
        // rar4-solid.cbr cannot be opened, but the library should list it and say
        // why — so the scan reports it as found, marked unopenable.
        assertTrue(LibraryScanner.scanAll(corpus).any { !it.isOpenable })
    }

    @Test
    fun `cancelling the consumer stops the walk`() = runTest {
        // `local-library` requires the scan to be cancellable. `take` cancels the
        // flow once it has what it asked for.
        val first = LibraryScanner.scan(corpus).take(2).toList()
        assertEquals(2, first.size)
    }

    // Folders as publications.

    @Test
    fun `a folder of images is one publication, not a shelf`() = runTest {
        val root = temp.newFolder()
        val comic = File(root, "Some Comic").apply { mkdirs() }
        repeat(3) { File(comic, "p${it + 1}.png").writeBytes(PNG) }

        val publications = LibraryScanner.scanAll(root)
        assertEquals(1, publications.size)
        assertEquals(PublicationFormat.IMAGE_FOLDER, publications.first().format)
        assertEquals(3, publications.first().pageCount)
    }

    @Test
    fun `a folder of comics is a shelf, and each comic is its own publication`() = runTest {
        val root = temp.newFolder()
        val shelf = File(root, "Series Name").apply { mkdirs() }
        val bytes = FixtureCorpus.file("comics/natural-sort.cbz").readBytes()
        for (name in listOf("Series 001.cbz", "Series 002.cbz")) {
            File(shelf, name).writeBytes(bytes)
        }

        val publications = LibraryScanner.scanAll(root)
        // Two publications, not one folder-shaped one — the directory holds
        // publications rather than pages.
        assertEquals(2, publications.size)
        assertTrue(publications.all { it.format == PublicationFormat.CBZ })
        assertEquals(listOf("1", "2"), publications.mapNotNull { it.number }.sorted())
    }

    @Test
    fun `an empty folder yields nothing and still finishes`() = runTest {
        val events = LibraryScanner.scan(temp.newFolder()).toList()
        assertEquals(listOf(ScanEvent.Finished(0, 0)), events)
    }

    @Test
    fun `a folder that does not exist finishes rather than hanging`() = runTest {
        val events = LibraryScanner.scan(File("/nowhere/at/all")).toList()
        assertEquals(listOf(ScanEvent.Finished(0, 0)), events)
    }

    private companion object {
        /** A 2x3 PNG, the same shape every committed fixture page uses. */
        val PNG = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x8D.toByte(), 0x6F, 0x26,
            0xD5.toByte(), 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
            0x54, 0x08, 0xD7.toByte(), 0x63, 0xF8.toByte(), 0xCF.toByte(), 0xC0.toByte(), 0x00,
            0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD.toByte(), 0x8D.toByte(),
            0xB0.toByte(), 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
            0x44, 0xAE.toByte(), 0x42, 0x60, 0x82.toByte(),
        )
    }
}
