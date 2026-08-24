package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Asserted against the shared corpus in `packages/test-fixtures`. iOS's
 * `EpubReaderTests` reads the same manifest, so neither platform can privately
 * redefine what a correct parse is.
 *
 * Three fixtures cover the four combinations `publication-formats` promises: EPUB
 * 3 reflowable, EPUB 2 reflowable, and EPUB 3 fixed-layout. EPUB 2 fixed-layout
 * does not exist — pre-pagination was introduced in EPUB 3.
 */
class EpubReaderTest {
    private val readable = listOf("fixture.epub", "epub2.epub", "fixed-layout.epub")

    private suspend fun reader(name: String) =
        EpubReader.open(FileSource(FixtureCorpus.file("ebooks/$name")))

    @Test
    fun `metadata matches the manifest`() = runTest {
        for (name in readable) {
            val fixture = FixtureCorpus.ebook(name)
            val reader = reader(name)
            assertEquals(name, fixture.expectedTitle, reader.metadata.title)
            assertEquals(name, fixture.expectedAuthor, reader.metadata.author)
            assertEquals(name, fixture.expectedLanguage, reader.metadata.language)
            assertEquals(name, fixture.expectedIdentifier, reader.metadata.identifier)
        }
    }

    @Test
    fun `the version is read from the package, not guessed`() = runTest {
        for (name in readable) {
            assertEquals(name, FixtureCorpus.ebook(name).epubVersion, reader(name).version)
        }
    }

    @Test
    fun `the spine is the reading order, with hrefs resolved`() = runTest {
        for (name in readable) {
            val fixture = FixtureCorpus.ebook(name)
            val reader = reader(name)
            assertEquals(name, fixture.expectedSpineCount, reader.spine.size)
            // Resolved against the package document's directory, not left relative:
            // `ch1.xhtml` in `OEBPS/package.opf` is `OEBPS/ch1.xhtml` in the
            // container.
            assertEquals(name, fixture.expectedSpineHrefs, reader.spine.map { it.href })
        }
    }

    @Test
    fun `spine items carry their media type`() = runTest {
        assertTrue(reader("fixture.epub").spine.all { it.mediaType == "application/xhtml+xml" })
    }

    // The two conventions per feature.

    @Test
    fun `the cover is found under either convention`() = runTest {
        for (name in readable) {
            val fixture = FixtureCorpus.ebook(name)
            val reader = reader(name)
            // EPUB 3 marks the cover with a manifest property; EPUB 2 names an item
            // id from a metadata meta. Both are pinned, because a version number is
            // not a promise about which convention a file actually used.
            assertEquals(name, fixture.expectedCoverHref, reader.coverHref)
            assertArrayEquals(
                name,
                byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
                reader.coverData()?.copyOfRange(0, 8),
            )
        }
    }

    @Test
    fun `the table of contents is read from a nav document or an ncx`() = runTest {
        for (name in readable) {
            val fixture = FixtureCorpus.ebook(name)
            // The EPUB 3 fixtures have a nav document; the EPUB 2 one has only an
            // NCX, reached through the spine's `toc` attribute rather than by media
            // type.
            assertEquals(name, fixture.expectedTocTitles, reader(name).toc.map { it.title })
        }
    }

    @Test
    fun `table-of-contents hrefs resolve and drop their fragments`() = runTest {
        assertEquals(
            listOf("OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"),
            reader("fixture.epub").toc.map { it.href },
        )
    }

    // Fixed layout.

    @Test
    fun `a pre-paginated publication says so, and a reflowable one does not`() = runTest {
        for (name in readable) {
            // Getting this wrong means offering typography controls for a comic,
            // which `ebook-reader` forbids.
            assertEquals(
                name,
                FixtureCorpus.ebook(name).isFixedLayout,
                reader(name).isFixedLayout,
            )
        }
    }

    // Reading content.

    @Test
    fun `a spine item's bytes come back`() = runTest {
        val reader = reader("fixture.epub")
        val text = String(reader.data(reader.spine.first().href))
        assertTrue(text.contains("Chapter One"))
    }

    // Refusals.

    @Test
    fun `a zip that is not an epub is refused as such`() = runTest {
        val failure = runCatching {
            EpubReader.open(FileSource(FixtureCorpus.file("comics/natural-sort.cbz")))
        }.exceptionOrNull()
        assertTrue("expected NotEpub, got $failure", failure is EpubException.NotEpub)
    }

    @Test
    fun `bytes that are not even a zip are refused`() = runTest {
        val failure = runCatching {
            EpubReader.open(DataSource(ByteArray(1024) { 0x41 }))
        }.exceptionOrNull()
        assertTrue("expected NotEpub, got $failure", failure is EpubException.NotEpub)
    }

    @Test
    fun `an epub with no container document is named, not silently empty`() = runTest {
        // The right mimetype and nothing else. Returning an empty publication
        // would put a book in the library that cannot be opened.
        val failure = runCatching {
            EpubReader.open(FileSource(FixtureCorpus.file("ebooks/no-package.epub")))
        }.exceptionOrNull()
        assertTrue(
            "expected NoPackageDocument, got $failure",
            failure is EpubException.NoPackageDocument,
        )
    }
}
