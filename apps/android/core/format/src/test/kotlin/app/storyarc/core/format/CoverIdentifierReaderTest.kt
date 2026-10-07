package app.storyarc.core.format

import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The identifier an EPUB's package document carries, as the cover lookup reads it.
 *
 * Task 6.1 of `cover-for-every-publication`: "an ISBN from an EPUB's OPF". The first
 * `dc:identifier` is usually a UUID and the ISBN is the second or third, so every one is
 * read. iOS's `CoverIdentifierReaderTests` is the twin of this file.
 */
class CoverIdentifierReaderTest {

    @get:Rule
    val folder = TemporaryFolder()

    private fun epub(vararg identifiers: String): ByteArray {
        val opf = """<?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata>
            <dc:title>Fine Print</dc:title>
            ${identifiers.joinToString("\n") { "<dc:identifier>$it</dc:identifier>" }}
            </metadata><manifest></manifest><spine></spine></package>"""
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            fun add(name: String, text: String) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
            add("mimetype", "application/epub+zip")
            add(
                "META-INF/container.xml",
                """<container><rootfiles><rootfile full-path="OEBPS/package.opf"/></rootfiles></container>""",
            )
            add("OEBPS/package.opf", opf)
        }
        return out.toByteArray()
    }

    private fun publication(format: PublicationFormat) = Publication(
        identity = PublicationIdentity(contentDigest = "digest"),
        format = format,
        displayTitle = "Fine Print",
        origin = MetadataOrigin.INFERRED,
    )

    private fun read(bytes: ByteArray, format: PublicationFormat = PublicationFormat.EPUB) =
        runBlocking { CoverIdentifierReader.identifier(publication(format), DataSource(bytes)) }

    @Test
    fun `an ISBN behind a UUID identifier is the one read`() {
        val found = read(epub("urn:uuid:5b4c1f9e-0c1d-4b5e-8f7a-1234567890ab", "urn:isbn:978-0-14-118776-1"))

        assertEquals(CoverIdentifier.Isbn("9780141187761"), found)
    }

    @Test
    fun `a bare ISBN is read as it is`() {
        assertEquals(CoverIdentifier.Isbn("9780141187761"), read(epub("9780141187761")))
    }

    @Test
    fun `an EPUB with no ISBN among its identifiers reads none`() {
        assertNull(read(epub("urn:uuid:5b4c1f9e-0c1d-4b5e-8f7a-1234567890ab", "not-a-number")))
    }

    @Test
    fun `a file that is no EPUB reads none rather than throw`() {
        assertNull(read(ByteArray(40) { 7 }))
    }

    @Test
    fun `a comic archive carries no identifier to read`() {
        assertNull(read(epub("9780141187761"), PublicationFormat.CBZ))
    }

    @Test
    fun `an audio folder is read through its first track`() = runBlocking {
        val track = byteArrayOf()
        val tracks = folder.newFolder("book")
        File(tracks, "02.mp3").writeBytes(track)
        File(tracks, "01.mp3").writeBytes(id3Asin("B08G9PRS1K"))

        val found = PublicationAccess.identifier(publication(PublicationFormat.AUDIO_FOLDER), tracks)

        assertEquals(CoverIdentifier.AudibleAsin("B08G9PRS1K"), found)
    }

    private fun id3Asin(asin: String): ByteArray {
        val body = byteArrayOf(0) + "ASIN".toByteArray() + byteArrayOf(0) + asin.toByteArray()
        val frame = "TXXX".toByteArray() + byteArrayOf(0, 0, 0, body.size.toByte(), 0, 0) + body
        return "ID3".toByteArray() + byteArrayOf(3, 0, 0, 0, 0, 0, frame.size.toByte()) + frame
    }
}
