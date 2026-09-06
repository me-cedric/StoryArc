package app.storyarc.core.format

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * A refusal is a case, not a sentence.
 *
 * `localization`'s *A refusal speaks the reader's language* and *A sentence built around
 * content*: the words a reader is shown come from the module that draws them, and the format
 * layer only says **which** refusal this is. [IndexException] used to carry
 * `Unreadable(val reason: String)`, and English sentences were written into it — in a module
 * with no string resources, where a translation gap cannot fail lint.
 *
 * This test drives the real corpus and asserts the case. It says nothing about words, which
 * is the point: `SkipReasonWordsTest` in `feature/library` owns those, because that is the
 * module with the four `strings.xml`.
 *
 * iOS's `SkipReasonIsClosedTests` asserts the same case names against the same fixtures.
 */
class SkipReasonIsClosedTest {

    @get:Rule
    val scratch = TemporaryFolder()

    private suspend fun refusalOf(file: File): SkipReason {
        val events = LibraryScanner.scan(file.parentFile!!).toList()
        val skipped = events.filterIsInstance<ScanEvent.Skipped>().single { it.path == file.name }
        return skipped.reason
    }

    /** A file whose bytes are what the test needs them to be. */
    private fun holding(name: String, bytes: String): File =
        scratch.newFolder().resolve(name).apply { writeText(bytes) }

    private fun copied(relativePath: String): File {
        val source = FixtureCorpus.file(relativePath)
        return scratch.newFolder().resolve(source.name).apply { source.copyTo(this) }
    }

    @Test
    fun `a file that is not there is its own case`() = runTest {
        val missing = File(scratch.newFolder(), "gone.cbz")

        val thrown = runCatching { PublicationIndexer.index(missing) }.exceptionOrNull()

        assertEquals(IndexException.NotThere::class, thrown!!::class)
    }

    @Test
    fun `bytes no sniffer recognises are their own case`() = runTest {
        assertEquals(
            SkipReason.FormatNotRecognised,
            refusalOf(holding("garbage.cbz", "this is not an archive")),
        )
    }

    @Test
    fun `a password-protected archive is its own case`() = runTest {
        assertEquals(
            SkipReason.ArchivePasswordProtected,
            refusalOf(copied("comics/password-protected.cbz")),
        )
    }

    @Test
    fun `a container StoryArc does not read names itself, and the name is content`() = runTest {
        assertEquals(
            SkipReason.UnsupportedFormat("CB7"),
            refusalOf(copied("comics/refused.cb7")),
        )
    }

    @Test
    fun `a locked audiobook is its own case and carries no key to ask for`() = runTest {
        assertEquals(
            SkipReason.ContentProtected,
            refusalOf(copied("audiobooks/protected.aax")),
        )
    }

    /**
     * The seam this change closes: what the scan hands the library.
     *
     * Three refusals of three kinds in one walk, each arriving as a case. A list where one row
     * is translated and another is not is the mixture `localization`'s *Reasons of different
     * kinds in one list* forbids, and it is only avoidable if every row is a case the drawing
     * module can word.
     */
    @Test
    fun `a scan reports every refusal as a case the library can word`() = runTest {
        val library = scratch.newFolder()
        for (path in listOf(
            "comics/refused.cb7",
            "comics/password-protected.cbz",
            "audiobooks/protected.aax",
        )) {
            val source = FixtureCorpus.file(path)
            source.copyTo(library.resolve(source.name))
        }

        val reasons = LibraryScanner.scan(library).toList()
            .filterIsInstance<ScanEvent.Skipped>()
            .associate { it.path to it.reason }

        assertEquals(SkipReason.UnsupportedFormat("CB7"), reasons["refused.cb7"])
        assertEquals(SkipReason.ArchivePasswordProtected, reasons["password-protected.cbz"])
        assertEquals(SkipReason.ContentProtected, reasons["protected.aax"])
        // The catch-all is for a failure nothing wrote a sentence for. A refusal the layer
        // does have a case for must never arrive as one, or the reader is told nothing.
        assertFalse(reasons.values.contains(SkipReason.Unknown))
    }
}
