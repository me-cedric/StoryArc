package app.storyarc.core.format

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The JVM half of cover loading: which bytes come out, and from where.
 *
 * Decoding those bytes into a `Bitmap` is a framework call, so it is asserted in
 * `CoverLoaderInstrumentedTest` instead. iOS tests both together because ImageIO
 * runs on the host — the split is in the platforms, not in the coverage.
 */
class CoverLoaderTest {
    private suspend fun publication(path: String): Pair<Publication, File> {
        val file = FixtureCorpus.file(path)
        return PublicationIndexer.index(file) to file
    }

    @Test
    fun `cover bytes come out of every container that stores one`() = runTest {
        for (path in listOf(
            "comics/natural-sort.cbz",
            "comics/tar-store.cbt",
            "comics/rar5-store.cbr",
            "ebooks/fixture.epub",
        )) {
            val (publication, file) = publication(path)
            val data = CoverLoader.coverData(publication, file)
            assertTrue(path, data.isNotEmpty())
            // Every fixture cover is a PNG, so the signature proves the right entry
            // was read rather than a header or the wrong page.
            assertArrayEquals(
                path,
                byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
                data.copyOfRange(0, 8),
            )
        }
    }

    @Test
    fun `a designated cover is the one loaded, not page one`() = runTest {
        val (publication, file) = publication("comics/manga-metadata.cbz")
        assertEquals("p2.png", publication.coverPath)
        val data = CoverLoader.coverData(publication, file)
        ComicArchiveOpener.open(file).use { archive ->
            val page = archive.pages.first { it.path == "p2.png" }
            // Loading the wrong page would still produce a valid image, which is
            // why the bytes are what get compared.
            assertArrayEquals(archive.data(page), data)
        }
    }

    @Test
    fun `a pdf has no stored cover, so it must be rendered instead`() = runTest {
        val (publication, file) = publication("comics/image-pages.pdf")
        assertNull(publication.coverPath)
        val failure = runCatching { CoverLoader.coverData(publication, file) }.exceptionOrNull()
        assertTrue("expected NoCover, got $failure", failure is CoverException.NoCover)
    }

    @Test
    fun `a publication with no pages has no cover to load`() = runTest {
        val (publication, file) = publication("comics/no-pages.cbz")
        assertNull(publication.coverPath)
        val failure = runCatching { CoverLoader.coverData(publication, file) }.exceptionOrNull()
        assertTrue("expected NoCover, got $failure", failure is CoverException.NoCover)
    }

    @Test
    fun `indexing does not decode a cover`() = runTest {
        // `publication-formats` requires the first screen of a 10,000-item scan
        // within three seconds, which is only possible if indexing records where the
        // cover is rather than reading it. The record is a path, not an image.
        assertEquals("p1.png", publication("comics/large-page.cbz").first.coverPath)
    }

    @Test
    fun `a share's own ranged reads give the same cover bytes as the file they read`() = runTest {
        // `PublicationAccess.anyCover` had no branch for a registered remote scheme and
        // fell to `File(path)`, which names nothing on the device -- a share's row never
        // drew a cover. This is the source-level half of that fix: the same bytes, read
        // through a `RandomAccessSource` instead of a `File`.
        val (publication, file) = publication("comics/natural-sort.cbz")
        val fromFile = CoverLoader.coverData(publication, file)
        val fromSource = CoverLoader.coverData(publication, FileSource(file))
        assertArrayEquals(fromFile, fromSource)
    }

    @Test
    fun `a share row with no recorded cover reads its own archive's cover`() = runTest {
        // `SmbContributor` catalogues a share row from its name alone: no cover path and no
        // page count. The comic branch required a cover path, so such a row never drew one,
        // over a share or anywhere else.
        val (indexed, file) = publication("comics/natural-sort.cbz")
        val row = Publication(
            identity = PublicationIdentity(normalizedPath = "smb://nas/Comics/natural-sort.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "Natural Sort",
            origin = MetadataOrigin.INFERRED,
        )
        assertArrayEquals(CoverLoader.coverData(indexed, file), CoverLoader.coverData(row, FileSource(file)))
    }
}
