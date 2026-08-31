package app.storyarc.core.format

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.StreamingCapability
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.IOException

/**
 * The seam between the format layer and the library, so these assert on what a
 * library row would show rather than on what a parser found. iOS's
 * `PublicationIndexerTests` asserts the same things.
 */
class PublicationIndexerTest {
    private suspend fun index(relativePath: String) =
        PublicationIndexer.index(FixtureCorpus.file(relativePath))

    @Test
    fun `every supported container indexes to its own format`() = runTest {
        assertEquals(PublicationFormat.CBZ, index("comics/natural-sort.cbz").format)
        assertEquals(PublicationFormat.CBT, index("comics/tar-store.cbt").format)
        assertEquals(PublicationFormat.CBR, index("comics/rar5-store.cbr").format)
        assertEquals(PublicationFormat.PDF, index("comics/text-pages.pdf").format)
        assertEquals(PublicationFormat.EPUB, index("ebooks/fixture.epub").format)
    }

    @Test
    fun `format comes from content, so a zip named cbr indexes as a cbz`() = runTest {
        // The same rule the archive layer follows, carried up to the library so a
        // filter by format does not lie about a mis-named file.
        assertEquals(PublicationFormat.CBZ, index("comics/mislabelled-zip.cbr").format)
    }

    @Test
    fun `an epub is told apart from a plain zip by its contents`() = runTest {
        // Both are ZIPs. Only the mimetype entry and the container document say
        // which, and guessing from the extension would put every EPUB in the comics
        // shelf.
        assertEquals(PublicationFormat.EPUB, index("ebooks/fixture.epub").format)
        assertEquals(PublicationFormat.CBZ, index("comics/natural-sort.cbz").format)
    }

    // Metadata precedence.

    @Test
    fun `embedded metadata beats the filename`() = runTest {
        val publication = index("comics/manga-metadata.cbz")
        assertEquals("Fixture Manga", publication.series)
        assertEquals("3", publication.number)
        assertEquals(2, publication.volume)
        assertEquals(2026, publication.year)
        assertEquals("Fixture Press", publication.publisher)
        assertEquals(listOf("First Writer", "Second Writer"), publication.authors)
        assertEquals(MetadataOrigin.EMBEDDED, publication.origin)
    }

    @Test
    fun `a file with no embedded metadata falls back to its filename, and says so`() = runTest {
        val publication = index("comics/natural-sort.cbz")
        assertEquals(MetadataOrigin.INFERRED, publication.origin)
        // The flag is the point: an authoritative source may replace this without
        // asking the user to resolve a conflict the app invented.
        assertTrue(publication.origin.yieldsTo(MetadataOrigin.AUTHORITATIVE))
        assertTrue(publication.origin.yieldsTo(MetadataOrigin.EMBEDDED))
    }

    @Test
    fun `embedded metadata does not yield to a filename guess`() = runTest {
        assertFalse(index("comics/manga-metadata.cbz").origin.yieldsTo(MetadataOrigin.INFERRED))
    }

    @Test
    fun `reading direction reaches the library, not just the parser`() = runTest {
        assertEquals(
            ReadingDirection.RIGHT_TO_LEFT,
            index("comics/manga-metadata.cbz").readingDirection,
        )
        assertEquals(
            ReadingDirection.RIGHT_TO_LEFT,
            index("comics/japanese-no-direction.cbz").readingDirection,
        )
        assertEquals(
            ReadingDirection.LEFT_TO_RIGHT,
            index("comics/natural-sort.cbz").readingDirection,
        )
    }

    @Test
    fun `a designated cover reaches the library`() = runTest {
        assertEquals("p2.png", index("comics/manga-metadata.cbz").coverPath)
        assertEquals("page1.png", index("comics/natural-sort.cbz").coverPath)
    }

    // What a row shows.

    @Test
    fun `a title is used when the file states one`() = runTest {
        assertEquals("The Third Chapter", index("comics/manga-metadata.cbz").displayTitle)
    }

    @Test
    fun `without a title, series and number are assembled`() = runTest {
        assertEquals(
            "Undeclared Direction",
            index("comics/japanese-no-direction.cbz").displayTitle,
        )
    }

    @Test
    fun `without either, the filename is shown rather than nothing`() = runTest {
        // A library row with no text at all is worse than one showing a filename.
        assertTrue(index("comics/natural-sort.cbz").displayTitle.isNotEmpty())
    }

    @Test
    fun `an epub's title comes from its package document`() = runTest {
        val publication = index("ebooks/fixture.epub")
        assertEquals("Fixture Publication", publication.displayTitle)
        assertEquals(listOf("StoryArc Fixtures"), publication.authors)
        assertEquals("en", publication.language)
        assertEquals(MetadataOrigin.EMBEDDED, publication.origin)
    }

    @Test
    fun `a fixed-layout epub is marked as one`() = runTest {
        // Drives which reader opens it, so a comic-as-EPUB is not offered font
        // controls it cannot honour.
        assertTrue(index("ebooks/fixed-layout.epub").isFixedLayout)
        assertFalse(index("ebooks/fixture.epub").isFixedLayout)
    }

    // Counts and capability.

    @Test
    fun `page count and skipped count are both recorded`() = runTest {
        val intact = index("comics/natural-sort.cbz")
        assertEquals(12, intact.pageCount)
        assertEquals(0, intact.skippedPageCount)
        assertFalse(intact.isPartial)

        val damaged = index("comics/truncated.cbz")
        assertTrue((damaged.pageCount ?: 0) > 0)
        assertTrue((damaged.pageCount ?: 99) < 12)
    }

    @Test
    fun `an epub records its spine length, not a page count`() = runTest {
        // An EPUB's pages depend on the type size the reader is set to, so there is
        // no page count to record.
        assertEquals(2, index("ebooks/fixture.epub").pageCount)
    }

    @Test
    fun `a pdf's page count is left for the reader on this platform`() = runTest {
        // PdfRenderer is a framework class, so touching it during a folder scan
        // would drag a device dependency into indexing. iOS reads it here because
        // PDFKit runs on the host; the field is nullable for exactly this reason.
        val publication = index("comics/text-pages.pdf")
        assertEquals(PublicationFormat.PDF, publication.format)
        assertNull(publication.pageCount)
    }

    @Test
    fun `streaming capability is recorded per publication`() = runTest {
        assertEquals(StreamingCapability.STREAMS, index("comics/natural-sort.cbz").streaming)
        assertEquals(StreamingCapability.STREAMS, index("comics/rar5-store.cbr").streaming)
        assertEquals(StreamingCapability.DOWNLOAD_ONLY, index("comics/rar5-solid.cbr").streaming)
        assertEquals(StreamingCapability.REFUSED, index("comics/rar4-solid.cbr").streaming)
    }

    @Test
    fun `a solid rar4 is listed and marked unopenable, not dropped`() = runTest {
        // The library should show it and say why. Dropping it silently leaves the
        // user hunting for a comic they can see in the folder.
        val publication = index("comics/rar4-solid.cbr")
        assertFalse(publication.isOpenable)
        assertTrue(publication.displayTitle.isNotEmpty())
    }

    // Refusals.

    @Test
    fun `a 7-zip comic is refused by name`() = runTest {
        val failure = runCatching { index("comics/refused.cb7") }.exceptionOrNull()
        assertTrue("expected Unsupported, got $failure", failure is IndexException.Unsupported)
        assertEquals("CB7", (failure as IndexException.Unsupported).format)
    }

    @Test
    fun `a file that is not there is named as missing, not as unsupported`() = runTest {
        val failure = runCatching {
            PublicationIndexer.index(File("/nowhere/at/all.cbz"))
        }.exceptionOrNull()
        assertTrue("expected Unreadable, got $failure", failure is IndexException.Unreadable)
    }

    @Test
    fun `a verification failure is not an io failure, so a caller has to name it`() = runTest {
        // `offline-downloads` verifies a finished download by indexing it, and the queue
        // that does the verifying has to catch what this throws. It caught `IOException`
        // and nothing else, and an index failure is not one -- so a truncated archive
        // threw out of the coroutine and took the app down instead of marking the
        // download failed. Pinned here because reparenting this type re-opens that.
        val failure = runCatching { index("comics/refused.cb7") }.exceptionOrNull()
        assertTrue("expected IndexException, got $failure", failure is IndexException)
        assertFalse("an index failure must not read as an io failure", failure is IOException)
    }

    // Identity.

    @Test
    fun `a scanned publication records both where it is and what it is`() = runTest {
        val publication = index("comics/natural-sort.cbz")
        assertTrue(publication.identity.normalizedPath != null)
        // The half that was missing: every library publication used to carry a path and
        // nothing else, so a rename lost the reader's place.
        assertTrue(publication.identity.contentDigest != null)
        assertFalse(publication.identity.isEmpty)
        // And the key it is filed under does not move because the digest arrived.
        assertTrue(publication.id.startsWith("path:"))
    }

    @Test
    fun `a content digest is stable, and differs between publications`() = runTest {
        val first = PublicationIndexer.contentDigest(FixtureCorpus.file("comics/natural-sort.cbz"))
        val again = PublicationIndexer.contentDigest(FixtureCorpus.file("comics/natural-sort.cbz"))
        val other = PublicationIndexer.contentDigest(
            FixtureCorpus.file("comics/nested-chapters.cbz"),
        )
        assertEquals(first, again)
        assertTrue(first != other)
        assertEquals(64, first.length)
    }

    @Test
    fun `the awkward archives all digest, and none collides`() = runTest {
        // The digest reads bytes and parses nothing, so the shapes that mislead a ZIP
        // parser cannot mislead it: a data descriptor zeroes the local headers, ZIP64
        // moves the end-of-directory record, an archive comment pushes it further, and a
        // truncated file has no readable directory at all.
        val paths = listOf(
            "comics/data-descriptor.cbz",
            "comics/zip64.cbz",
            "comics/truncated.cbz",
            "comics/natural-sort.cbz",
            "comics/archive-comment.cbz",
        )
        val digests = paths.map { PublicationIndexer.contentDigest(FixtureCorpus.file(it)) }
        digests.forEach { assertEquals(64, it.length) }
        assertEquals(paths.size, digests.toSet().size)
    }

    @Test
    fun `an archive too broken to index still has an identity`() = runTest {
        // `truncated.cbz` is the case that proves bytes beat parsing. Whatever the
        // library decides to do with it, the reader's place in it is still findable.
        val digest = PublicationIndexer.contentDigest(FixtureCorpus.file("comics/truncated.cbz"))
        assertEquals(64, digest.length)
    }

    @Test
    fun `a renamed file is the same publication`() = runTest {
        // The defect this exists for. A copy at another path under another name is the
        // same bytes, so the two identities match and the progress store finds one
        // record — while each is still filed under its own path.
        val directory = File.createTempFile("storyarc-digest", "").let {
            it.delete()
            it.mkdirs()
            it
        }
        try {
            val moved = File(directory, "Renamed Entirely.cbz")
            FixtureCorpus.file("comics/natural-sort.cbz").copyTo(moved)

            val before = index("comics/natural-sort.cbz")
            val after = PublicationIndexer.index(moved)

            assertEquals(before.identity.contentDigest, after.identity.contentDigest)
            assertTrue(before.identity.matches(after.identity))
            assertTrue(before.id != after.id)
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun `something with no file of its own has no digest`() = runTest {
        // A folder of images. There are no file bytes to hash, and the honest answer is
        // no digest rather than a digest of a directory entry — which would differ
        // between two devices holding the same pages.
        val directory = File.createTempFile("storyarc-nodigest", "").let {
            it.delete()
            it.mkdirs()
            it
        }
        try {
            val digest = runCatching {
                PublicationIndexer.contentDigest(directory)
            }.getOrNull()
            assertNull(digest)
        } finally {
            directory.deleteRecursively()
        }
    }

    // What the digest is computed from.

    /**
     * A source both platforms can build byte for byte, so the expectation below is a
     * number rather than a description. Deliberately not a fixture: regenerating the
     * corpus can change DEFLATE output, and this has to pin the algorithm and only the
     * algorithm.
     */
    private fun pattern(count: Int) = DataSource(ByteArray(count) { ((it * 31 + 7) % 251).toByte() })

    @Test
    fun `the digest is length, then head, then tail -- pinned to the byte`() = runTest {
        // SHA-256 over the length as eight little-endian bytes, the first 512 KB, and the
        // last 512 KB. **The same literal appears in iOS's `PublicationIndexerTests`.**
        // If one platform's changes, both must — that is what stops a reader's place from
        // being lost on one platform only.
        val digest = PublicationIndexer.contentDigest(pattern(1_100_000))
        assertEquals("434c6d7af16982446617ca1ea7fc5cd0ff1e1d8915ea38628c83b136bf2cb0e6", digest)
    }

    @Test
    fun `a source smaller than the window is hashed once, not twice`() = runTest {
        // The head already covered every byte there is, so the tail is skipped rather
        // than folded in again. Mirrored literal, same rule as above.
        val digest = PublicationIndexer.contentDigest(pattern(1000))
        assertEquals("b00eef232e60114f7bb29c94548f243823c9c75291714ab0bd2c8787d9a03c5d", digest)
    }

    @Test
    fun `length is part of the digest, not just the bytes at each end`() = runTest {
        // Identical head, identical tail, one byte longer. Without the length in the hash
        // these would be the same publication.
        val shorter = PublicationIndexer.contentDigest(DataSource(ByteArray(600_000)))
        val longer = PublicationIndexer.contentDigest(DataSource(ByteArray(600_001)))
        assertTrue(shorter != longer)
    }

    @Test
    fun `two files differing only in the middle are not told apart`() = runTest {
        // Asserted rather than left to be discovered. Reading a megabyte instead of four
        // hundred is what makes this cheap enough to run on every publication a folder
        // walk finds, and this is the price: a change beyond the first 512 KB and before
        // the last 512 KB, with the length unmoved, is invisible.
        val bytes = ByteArray(1_100_000) { ((it * 31 + 7) % 251).toByte() }
        val original = PublicationIndexer.contentDigest(DataSource(bytes))
        bytes[550_000] = (bytes[550_000] + 1).toByte()
        val altered = PublicationIndexer.contentDigest(DataSource(bytes))
        assertEquals(original, altered)
    }
}
