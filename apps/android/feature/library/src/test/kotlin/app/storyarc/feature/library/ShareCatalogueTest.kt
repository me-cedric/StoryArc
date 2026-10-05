package app.storyarc.feature.library

import app.storyarc.core.format.FileSource
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.StreamingCapability
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/**
 * D28: a share row catalogued from its own headers rather than from its file name.
 *
 * The share itself is stood in for by a fixture behind [ShareCatalogue.catalogued]'s opener,
 * which is what that parameter is for -- the decision being asserted is what a header read
 * changes about a row, and that has nothing to do with SMB. iOS asserts the same cases in
 * `ShareCatalogueTests.swift`.
 */
class ShareCatalogueTest {

    private val sourceId = UUID.randomUUID()

    /**
     * A row exactly as [SmbContributor] builds one: the extension's claim, the optimistic
     * default, no page count and no cover.
     */
    private fun row(
        name: String,
        format: PublicationFormat,
        streaming: StreamingCapability = StreamingCapability.STREAMS,
    ) = Publication(
        identity = PublicationIdentity(
            normalizedPath = "smb://nas.local/Comics/Lantern%20Green/$name",
        ),
        format = format,
        displayTitle = name.substringBeforeLast('.'),
        origin = MetadataOrigin.INFERRED,
        streaming = streaming,
        sourceId = sourceId,
        fileSize = 400_000_000,
    )

    /**
     * One real archive from the shared corpus. `core:format`'s own `FixtureCorpus` is not on
     * this module's test path, so the walk-up it falls back to is repeated here, as
     * `KavitaChapterQueueTest` already repeats it.
     */
    private fun fixture(relativePath: String): File {
        var directory: File? = File("").absoluteFile
        while (directory != null) {
            val corpus = File(directory, "packages/test-fixtures")
            if (File(corpus, "manifest.json").isFile) return File(corpus, relativePath)
            directory = directory.parentFile
        }
        error("fixture corpus not found above ${File("").absolutePath}")
    }

    private suspend fun catalogued(row: Publication, relativePath: String): Publication? =
        ShareCatalogue.catalogued(row) { FileSource(fixture(relativePath)) }

    @Test
    fun `a share row's format comes from its headers, not from its extension`() = runTest {
        val found = catalogued(
            row("mislabelled-zip.cbr", PublicationFormat.CBR),
            "comics/mislabelled-zip.cbr",
        )

        assertEquals(PublicationFormat.CBZ, found?.format)
        assertEquals(3, found?.pageCount)
        assertEquals("page1.png", found?.coverPath)
        assertEquals(StreamingCapability.STREAMS, found?.streaming)
    }

    @Test
    fun `a solid RAR4 on a share is refused on the shelf, before a reader taps it`() = runTest {
        val found = catalogued(row("rar4-solid.cbr", PublicationFormat.CBR), "comics/rar4-solid.cbr")

        assertEquals(StreamingCapability.REFUSED, found?.streaming)
        assertFalse(found!!.isOpenable)
    }

    @Test
    fun `what only the share's walk knew survives the merge`() = runTest {
        val walked = row("mislabelled-zip.cbr", PublicationFormat.CBR)

        val found = catalogued(walked, "comics/mislabelled-zip.cbr")

        assertEquals(walked.id, found?.id)
        assertEquals(sourceId, found?.sourceId)
        assertEquals(400_000_000L, found?.fileSize)
    }

    @Test
    fun `a catalogued row is not asked for its headers a second time`() = runTest {
        val walked = row("mislabelled-zip.cbr", PublicationFormat.CBR)
        assertTrue(ShareCatalogue.needsCataloguing(walked))

        val found = catalogued(walked, "comics/mislabelled-zip.cbr")

        assertFalse(ShareCatalogue.needsCataloguing(found!!))
    }

    @Test
    fun `a row that is already refused by name is left alone`() {
        val seven = row("refused.cb7", PublicationFormat.CB7, StreamingCapability.REFUSED)

        assertFalse(ShareCatalogue.needsCataloguing(seven))
    }

    @Test
    fun `a publication on this device is not a share row`() {
        val local = Publication(
            identity = PublicationIdentity(normalizedPath = "/storage/Comics/natural-sort.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "natural-sort",
            origin = MetadataOrigin.INFERRED,
        )

        assertFalse(ShareCatalogue.needsCataloguing(local))
    }

    @Test
    fun `a share that does not answer leaves the row as the walk left it`() = runTest {
        val walked = row("mislabelled-zip.cbr", PublicationFormat.CBR)

        val found = ShareCatalogue.catalogued(walked) { error("the share is unreachable") }

        assertNull(found)
    }
}
