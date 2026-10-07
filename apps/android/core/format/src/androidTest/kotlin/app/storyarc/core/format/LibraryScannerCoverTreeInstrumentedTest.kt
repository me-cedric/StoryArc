package app.storyarc.core.format

import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import java.io.File
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Task 6.6, which closes task 1.1: the scanner, run over a content tree with a cover directory.
 *
 * Task 1.1 passed the cover directory to both Storage Access Framework call sites in
 * [LibraryScanner] -- `scan` and `index` -- and no test ran either of them. `looseCoverFrom` was
 * asserted on a plain JVM, which proves the rule and not that the call sites hand it anything.
 * A call site that passed `null`, or one that rebuilt an audiobook folder as comic pages, left
 * every test green and every picked audiobook with a glyph.
 *
 * The tree is two audiobook folders, each with two parts and its own cover image, served by
 * [TestTreeProvider] so the walk reaches them through `DocumentsContract` as it does in the app.
 * Two folders and two different pictures, because one folder cannot tell "each book keeps its
 * own cover" from "every book got the first cover found".
 */
@RunWith(AndroidJUnit4::class)
class LibraryScannerCoverTreeInstrumentedTest {

    private val context = InstrumentationRegistry.getInstrumentation().context
    private val resolver get() = context.contentResolver

    private val alphaCover = byteArrayOf(1, 1, 1, 1)
    private val betaCover = byteArrayOf(2, 2, 2, 2, 2, 2)

    private lateinit var work: File
    private lateinit var covers: File
    private lateinit var tree: Uri

    @Before
    fun serveATree() {
        work = File(context.cacheDir, "scanner-cover-tree").also { it.deleteRecursively() }
        val library = File(work, "library")
        folder(library, "Alpha Book", alphaCover)
        folder(library, "Beta Book", betaCover)
        covers = File(work, "covers")
        TestTreeProvider.base = library
        tree = DocumentsContract.buildTreeDocumentUri(
            TestTreeProvider.AUTHORITY,
            TestTreeProvider.ROOT,
        )
    }

    @After
    fun removeTheTree() {
        work.deleteRecursively()
    }

    @Test
    fun aScanGivesEachAudiobookItsOwnCover(): Unit = runBlocking {
        val found = LibraryScanner.scan(resolver, tree, coverCacheDir = covers)
            .filterIsInstance<ScanEvent.Found>()
            .map { it.publication }
            .toList()

        assertEachBookKeepsItsOwnCover(found)
    }

    @Test
    fun theIncrementalIndexGivesEachAudiobookItsOwnCover(): Unit = runBlocking {
        val listed = LibraryScanner.listing(resolver, tree).filter { it.isFolder }

        val indexed = listed.map { LibraryScanner.index(resolver, tree, it, covers) }

        assertEquals("both folders are listed as publications", 2, listed.size)
        assertEachBookKeepsItsOwnCover(indexed)
    }

    @Test
    fun theIncrementalIndexDoesNotReadAnAudiobookFolderAsComicPages(): Unit = runBlocking {
        val listed = LibraryScanner.listing(resolver, tree).first { it.name == "Alpha Book" }

        val publication = LibraryScanner.index(resolver, tree, listed, covers)

        assertEquals(PublicationFormat.AUDIO_FOLDER, publication.format)
        assertEquals("its two parts, not the pages of a comic", 2, publication.pageCount)
    }

    @Test
    fun withNoCoverDirectoryTheScanStillIndexesAndRecordsNoCover(): Unit = runBlocking {
        val found = LibraryScanner.scan(resolver, tree)
            .filterIsInstance<ScanEvent.Found>()
            .map { it.publication }
            .toList()

        assertEquals(2, found.size)
        assertTrue(found.all { it.coverPath == null })
    }

    private fun assertEachBookKeepsItsOwnCover(books: List<Publication>) {
        assertEquals(2, books.size)
        val byName = books.associateBy { it.displayTitle }
        val alpha = byName.entries.first { "Alpha" in it.key }.value
        val beta = byName.entries.first { "Beta" in it.key }.value

        assertTrue("both are audiobooks", books.all { it.format == PublicationFormat.AUDIO_FOLDER })
        assertNotNull("Alpha records where its cover went", alpha.coverPath)
        assertNotNull("Beta records where its cover went", beta.coverPath)
        assertNotEquals("each book has a path of its own", alpha.coverPath, beta.coverPath)
        assertTrue(File(alpha.coverPath!!).readBytes().contentEquals(alphaCover))
        assertTrue(File(beta.coverPath!!).readBytes().contentEquals(betaCover))
        assertFalse(
            "the two covers are different files with different contents",
            File(alpha.coverPath!!).readBytes().contentEquals(File(beta.coverPath!!).readBytes()),
        )
    }

    private fun folder(library: File, name: String, cover: ByteArray) {
        val directory = File(library, name).also { it.mkdirs() }
        File(directory, "part 01.mp3").writeBytes(ByteArray(8))
        File(directory, "part 02.mp3").writeBytes(ByteArray(8))
        File(directory, "cover.jpg").writeBytes(cover)
    }
}
