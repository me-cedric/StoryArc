package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Asserted against the shared corpus in `packages/test-fixtures`, using the
 * expectations recorded in its `manifest.json`. iOS's `ComicArchiveTests` reads
 * the same manifest, so neither platform can privately redefine what a correct
 * parse is.
 */
class ComicArchiveTest {
    private fun open(name: String) = ComicArchiveOpener.open(FixtureCorpus.file("comics/$name"))

    @Test
    fun `every fixture parses to the page order its manifest records`() {
        val names = listOf(
            "natural-sort.cbz",
            "nested-chapters.cbz",
            "non-image-entries.cbz",
            "mislabelled-zip.cbr",
            "single-page.cbz",
            "double-page-spread.cbz",
            "no-pages.cbz",
        )
        for (name in names) {
            val fixture = FixtureCorpus.comic(name)
            open(name).use { archive ->
                assertEquals("$name: ${fixture.pins}", fixture.expectedPageCount, archive.pages.size)
                assertEquals(
                    "$name: ${fixture.pins}",
                    fixture.expectedPageOrder,
                    archive.pages.map { it.path },
                )
            }
        }
    }

    @Test
    fun `a ZIP named cbr opens, because format comes from content not extension`() {
        val file = FixtureCorpus.file("comics/mislabelled-zip.cbr")

        assertEquals(FormatSniffer.Container.ZIP, FormatSniffer.container(file))
        open("mislabelled-zip.cbr").use { assertEquals(3, it.pages.size) }
    }

    @Test
    fun `an archive with no images reports zero pages rather than failing`() {
        open("no-pages.cbz").use { archive ->
            assertTrue(archive.pages.isEmpty())
            assertEquals(0, archive.skippedPageCount)
        }
    }

    @Test
    fun `a truncated archive fails as unreadable rather than crashing or hanging`() {
        // `publication-formats` wants partial recovery. `ZipFile` cannot offer it
        // once the central directory is gone, so the honest behaviour today is a
        // clean Unreadable — recorded here so the day a recovering reader lands,
        // this test is what changes.
        assertThrows(ComicArchiveException.Unreadable::class.java) { open("truncated.cbz") }
    }

    @Test
    fun `page bytes decode back to the PNG that was packed`() {
        open("natural-sort.cbz").use { archive ->
            val data = archive.data(archive.pages.first())

            assertTrue(data.isNotEmpty())
            // PNG magic — proves the bytes are the page and not a header or padding.
            assertEquals(0x89.toByte(), data[0])
            assertEquals('P'.code.toByte(), data[1])
            assertEquals('N'.code.toByte(), data[2])
            assertEquals('G'.code.toByte(), data[3])
        }
    }

    @Test
    fun `ComicInfo xml is captured as metadata, not served as a page`() {
        (open("non-image-entries.cbz") as ZipComicArchive).use { archive ->
            assertEquals(listOf("page1.png", "page2.png"), archive.pages.map { it.path })
            val xml = requireNotNull(archive.comicInfoData).decodeToString()
            assertTrue(xml.contains("Fixture Series"))
        }
    }

    @Test
    fun `reading every page skips nothing in a healthy archive`() {
        (open("natural-sort.cbz") as ZipComicArchive).use { archive ->
            assertEquals(archive.pages.size, archive.readableData(archive.pages).size)
        }
    }
}

class FormatSnifferTest {
    @Test
    fun `ZIP, RAR 4, RAR 5, 7-Zip and PDF are identified from their magic bytes`() {
        assertEquals(
            FormatSniffer.Container.ZIP,
            FormatSniffer.container(byteArrayOf(0x50, 0x4B, 0x03, 0x04)),
        )
        assertEquals(
            FormatSniffer.Container.RAR,
            FormatSniffer.container(byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00)),
        )
        assertEquals(
            FormatSniffer.Container.RAR,
            FormatSniffer.container(byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00)),
        )
        assertEquals(
            FormatSniffer.Container.SEVEN_ZIP,
            FormatSniffer.container(byteArrayOf(0x37, 0x7A, 0xBC.toByte(), 0xAF.toByte(), 0x27, 0x1C)),
        )
        assertEquals(
            FormatSniffer.Container.PDF,
            FormatSniffer.container(byteArrayOf(0x25, 0x50, 0x44, 0x46, 0x2D)),
        )
    }

    @Test
    fun `unrecognised bytes return null rather than guessing`() {
        assertEquals(null, FormatSniffer.container(byteArrayOf(0x00, 0x01, 0x02, 0x03)))
        assertEquals(null, FormatSniffer.container(byteArrayOf()))
    }

    @Test
    fun `a RAR names its container so the user is told what they actually have`() {
        // ADR-0005: CBR is blocked on a licence review, not on capability. The
        // exception carries the container so the message can say "RAR", which is
        // more useful than a generic failure.
        val tmp = File.createTempFile("fake", ".cbr")
        try {
            tmp.writeBytes(byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00))
            val thrown = assertThrows(ComicArchiveException.UnsupportedContainer::class.java) {
                ComicArchiveOpener.open(tmp)
            }
            assertEquals(FormatSniffer.Container.RAR, thrown.container)
        } finally {
            tmp.delete()
        }
    }

    @Test
    fun `only the first few bytes are read, so probing a remote file is cheap`() {
        // The value matters: `network-share` requires opening a 400 MB archive
        // over SMB without transferring it, and sniffing is the first read.
        assertTrue(FormatSniffer.PROBE_LENGTH <= 16)
    }
}
