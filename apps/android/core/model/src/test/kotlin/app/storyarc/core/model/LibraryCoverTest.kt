package app.storyarc.core.model

import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `library-portability` tasks 2.1 and 6.7: a cover the reader chose travels in the document.
 * iOS's `LibraryCoverTests` asserts the same rows against the same fixture.
 */
class LibraryCoverTest {

    private val document = LibraryExport.document(
        LibraryDocumentFixture.snapshot,
        LibraryDocumentFixture.APP_VERSION,
        LibraryDocumentFixture.WRITTEN_AT,
    )

    private fun carrying(vararg covers: DocumentCover) =
        document.copy(library = document.library.copy(covers = covers.toList()))

    private fun base64(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)

    @Test
    fun `export writes each chosen cover as its key and its image in base64`() {
        assertEquals(
            listOf(
                DocumentCover(
                    LibraryDocumentFixture.COVER_KEY,
                    base64(LibraryDocumentFixture.coverImage),
                ),
            ),
            document.library.covers,
        )
    }

    @Test
    fun `a cover survives a write and a read through the coder, byte for byte`() {
        val read = LibraryDocumentCoder.decode(LibraryDocumentCoder.encode(document)).getOrThrow()
        val landed = LibraryImport.merging(read, LibrarySnapshot()).snapshot

        assertEquals(
            listOf(ChosenCover(LibraryDocumentFixture.COVER_KEY, LibraryDocumentFixture.coverImage)),
            landed.covers,
        )
    }

    @Test
    fun `a cover the device already holds under the same key stands`() {
        val device = LibrarySnapshot(
            covers = listOf(ChosenCover(LibraryDocumentFixture.COVER_KEY, byteArrayOf(1, 2, 3))),
        )

        val landed = LibraryImport.merging(document, device).snapshot

        assertEquals(device.covers, landed.covers)
        assertEquals(0, LibraryImport.plan(document, device).coversToAdd)
    }

    @Test
    fun `the preview counts a cover that will arrive`() {
        assertEquals(1, LibraryImport.plan(document, LibrarySnapshot()).coversToAdd)
    }

    @Test
    fun `an image that is not base64, is empty or is over the ceiling is dropped, and only it`() {
        val tooBig = base64(ByteArray(LibraryImport.MAXIMUM_COVER_BYTES + 1))
        val carrying = carrying(
            DocumentCover("sha:good", base64(LibraryDocumentFixture.coverImage)),
            DocumentCover("sha:notbase64", "***"),
            DocumentCover("sha:empty", ""),
            DocumentCover("sha:big", tooBig),
        )

        val landed = LibraryImport.merging(carrying, LibrarySnapshot()).snapshot

        assertEquals(listOf("sha:good"), landed.covers.map { it.key })
        assertEquals(3, landed.sources.sources.size)
        assertEquals(1, LibraryImport.plan(carrying, LibrarySnapshot()).coversToAdd)
    }

    @Test
    fun `an image exactly at the ceiling is kept`() {
        val atCeiling = base64(ByteArray(LibraryImport.MAXIMUM_COVER_BYTES))

        val landed = LibraryImport.merging(
            carrying(DocumentCover("sha:edge", atCeiling)),
            LibrarySnapshot(),
        ).snapshot

        assertEquals(listOf("sha:edge"), landed.covers.map { it.key })
    }

    @Test
    fun `the key a publication's cover is filed under is its digest, else its stable identifier`() {
        assertEquals(
            "sha:d1",
            PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz").coverOverrideKey,
        )
        assertEquals(
            "path:/a.cbz",
            PublicationIdentity(normalizedPath = "/a.cbz").coverOverrideKey,
        )
    }
}
