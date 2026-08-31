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

    /**
     * A throwaway library laid out the way a real one is: a folder per series,
     * numbered files inside it.
     */
    private fun shelf(series: String, files: List<String>): File {
        val root = temp.newFolder()
        val folder = File(root, series).apply { mkdirs() }
        files.forEachIndexed { index, source ->
            File(corpus, "comics/$source").copyTo(File(folder, "%02d.cbz".format(index + 1)))
        }
        return root
    }

    @Test
    fun `a subfolder names the series when the filename does not`() = runTest {
        // `local-library`: "each subfolder is presented as a series whose name is
        // the folder name". "Bone/01.cbz" says which issue it is and not which
        // series; the folder is the only thing that knows.
        val root = shelf("Bone", listOf("single-page.cbz", "natural-sort.cbz"))

        val publications = LibraryScanner.scanAll(root)

        assertEquals(2, publications.size)
        assertTrue(publications.all { it.series == "Bone" })
        assertEquals(setOf("1", "2"), publications.mapNotNull { it.number }.toSet())
    }

    @Test
    fun `the library's own folder is not a series`() = runTest {
        // Everything in the corpus root would otherwise be filed under
        // "test-fixtures", which is a path, not a story.
        val publications = LibraryScanner.scanAll(corpus)
        assertTrue(publications.none { it.series == corpus.name })
    }

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

    @Test
    fun `the listing holds everything the scan found`() = runTest {
        // The two walks are compared against each other by every reconcile, so a file the
        // scan finds and the listing misses would be removed from the library the first time
        // it was reconciled, and found again by the next full scan.
        val scanned = LibraryScanner.scanAll(corpus).mapNotNull { it.identity.normalizedPath }
        val listed = LibraryScanner.entries(corpus).map { it.path }.toSet()
        assertTrue(listed.containsAll(scanned))
    }

    @Test
    fun `the listing also holds what the scan refused`() {
        // Deliberately wider than the scan. A file StoryArc will not open is still a file
        // that was there, and a listing that left it out would report it as newly arrived on
        // every single pass -- which is the opposite of noticing a change.
        val listed = LibraryScanner.entries(corpus).map { it.path }
        assertTrue(listed.any { it.endsWith("refused.cb7") })
    }

    @Test
    fun `a listing carries a size and a time for every entry`() {
        // Either alone misses a real case: a file replaced with one of the same length keeps
        // its size, and one restored from a backup keeps its time.
        val listed = LibraryScanner.entries(shelf("Bone", listOf("single-page.cbz")))
        assertEquals(1, listed.size)
        assertTrue(listed.first().size > 0)
        assertTrue(listed.first().modifiedAtEpochMillis > 0)
    }

    @Test
    fun `a folder that cannot be read lists nothing rather than throwing`() {
        // Which is what makes the snapshot's refusal reachable: the empty list is the signal
        // that the folder could not be walked, and it must arrive rather than crash.
        assertTrue(LibraryScanner.entries(File("/nowhere/at/all")).isEmpty())
    }

    @Test
    fun `a resumed scan does not open what the interrupted one already did`() = runTest {
        // `local-library`: a scan "is cancellable and resumable". Resumable means this and
        // nothing else -- the archives already read are not read again, which is where the
        // minutes of a ten-thousand-file scan go.
        val root = shelf("Bone", listOf("single-page.cbz", "natural-sort.cbz"))
        val first = LibraryScanner.scanAll(root)
        val done = first.mapNotNull { it.identity.normalizedPath }.take(1).toSet()

        val resumed = LibraryScanner.scan(root, done).toList()
            .filterIsInstance<ScanEvent.Found>()
            .map { it.publication }

        assertEquals(1, resumed.size)
        assertTrue(resumed.none { it.identity.normalizedPath in done })
    }

    @Test
    fun `a resumed scan that has nothing left to do finds nothing and still finishes`() = runTest {
        // The end of a resume, and the state a reader is in when the process was reclaimed
        // one file from the end. It must finish rather than report the whole folder again.
        val root = shelf("Bone", listOf("single-page.cbz"))
        val done = LibraryScanner.scanAll(root).mapNotNull { it.identity.normalizedPath }.toSet()
        assertEquals(
            listOf(ScanEvent.Finished(0, 0)),
            LibraryScanner.scan(root, done).toList(),
        )
    }

    // Audiobooks, and the gate that used to stop them.
    //
    // `PublicationIndexer` learned to build an audiobook before the scanner learned to
    // hand it one: a candidate-extension pre-filter with no audio in it, and a folder rule
    // that counted only images. Both branches are asserted here because the walk decides
    // things the indexer never sees.

    @Test
    fun `a folder of only audio is one audiobook, not a shelf of one-part books`() = runTest {
        // `publication-formats`: a folder of ordered audio "is treated as a single
        // audiobook whose parts play in that order". Put the parts in
        // `CANDIDATE_EXTENSIONS` and this becomes three publications of one track each,
        // which is the failure this pins.
        val root = temp.newFolder()
        val folder = File(root, "Sea Room").apply { mkdirs() }
        for (part in listOf("part1.mp3", "part2.mp3", "part10.mp3")) {
            File(corpus, "audiobooks/folder-parts/$part").copyTo(File(folder, part))
        }

        val publications = LibraryScanner.scanAll(root)

        assertEquals(1, publications.size)
        assertEquals(PublicationFormat.AUDIO_FOLDER, publications.single().format)
        assertEquals(3, publications.single().pageCount)
    }

    @Test
    fun `audio beside containers is a publication of its own`() = runTest {
        // The other branch, and the reason it exists: a lone `.m4b` in a folder of comics
        // is a book, and before this it was skipped without a word. A directory holding
        // containers takes the per-file path, so the audio has to be named there too.
        val root = temp.newFolder()
        File(corpus, "comics/natural-sort.cbz").copyTo(File(root, "natural-sort.cbz"))
        File(corpus, "audiobooks/chaptered.m4b").copyTo(File(root, "chaptered.m4b"))

        val formats = LibraryScanner.scanAll(root).map { it.format }.toSet()

        assertTrue("the comic is gone", PublicationFormat.CBZ in formats)
        assertTrue("the audiobook was skipped", PublicationFormat.M4B in formats)
    }

    @Test
    fun `images beside containers are still not publications`() = runTest {
        // The asymmetry above is deliberate, so it is pinned rather than left to be read
        // as an oversight. An `.m4b` is a whole publication in one file, exactly like a
        // `.cbz`; a loose `.png` beside a pile of comics is a cover or a scan artefact.
        val root = temp.newFolder()
        File(corpus, "comics/natural-sort.cbz").copyTo(File(root, "natural-sort.cbz"))
        File(root, "loose-page.png").writeBytes(PNG)

        val publications = LibraryScanner.scanAll(root)

        assertEquals(1, publications.size)
        assertEquals(PublicationFormat.CBZ, publications.single().format)
    }

    @Test
    fun `a protected audiobook is skipped by name rather than listed`() = runTest {
        // `publication-formats`: the refusal is "distinct from an unsupported container".
        // The scan reports it as skipped with the protection as the reason, and the
        // library does not offer a row that cannot be opened.
        val root = temp.newFolder()
        File(corpus, "comics/natural-sort.cbz").copyTo(File(root, "natural-sort.cbz"))
        File(corpus, "audiobooks/protected.aax").copyTo(File(root, "protected.aax"))

        val events = LibraryScanner.scan(root, emptySet()).toList()
        val skipped = events.filterIsInstance<ScanEvent.Skipped>()

        assertEquals(1, skipped.size)
        assertTrue(
            "the reason does not name the protection: ${skipped.single().reason}",
            skipped.single().reason.contains("content protection"),
        )
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
