package app.storyarc.core.format

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
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
    private suspend fun open(name: String) = ComicArchiveOpener.open(FixtureCorpus.file("comics/$name"))

    @Test
    fun `every fixture parses to the page order its manifest records`() = runTest {
        val names = listOf(
            "natural-sort.cbz",
            "nested-chapters.cbz",
            "non-image-entries.cbz",
            "mislabelled-zip.cbr",
            "single-page.cbz",
            "double-page-spread.cbz",
            "no-pages.cbz",
            "stored-entries.cbz",
            "zip64.cbz",
            "archive-comment.cbz",
            "data-descriptor.cbz",
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
    fun `a ZIP named cbr opens, because format comes from content not extension`() = runTest {
        val file = FixtureCorpus.file("comics/mislabelled-zip.cbr")

        assertEquals(FormatSniffer.Container.ZIP, FormatSniffer.container(file))
        open("mislabelled-zip.cbr").use { assertEquals(3, it.pages.size) }
    }

    @Test
    fun `an archive with no images reports zero pages rather than failing`() = runTest {
        open("no-pages.cbz").use { archive ->
            assertTrue(archive.pages.isEmpty())
            assertEquals(0, archive.skippedPageCount)
        }
    }

    @Test
    fun `an entry with nothing in it is counted as skipped rather than listed as a page`() =
        runTest {
            // `publication-formats`: a damaged archive opens "whatever pages it can read
            // and states how many were skipped". The count is the stating.
            val fixture = FixtureCorpus.comic("unsupported-codec.cbz")
            open("unsupported-codec.cbz").use { archive ->
                assertEquals(fixture.expectedSkippedPageCount, archive.skippedPageCount)
                assertEquals(fixture.expectedPageOrder, archive.pages.map { it.path })
            }
        }

    @Test
    fun `a page in a codec nothing decodes is still a page, and is named`() = runTest {
        // The whole of the requirement: the page stays in the list, "does not break
        // pagination", and the placeholder that stands in for it names the codec.
        // Excluding it would be the easy fix and the wrong one — a page nobody can be
        // told about is a page the reader silently loses.
        val fixture = FixtureCorpus.comic("unsupported-codec.cbz")
        open("unsupported-codec.cbz").use { archive ->
            val page = archive.pages.first { it.path.endsWith(".jxl") }
            val data = archive.data(page)
            assertEquals(
                fixture.expectedUndecodableCodec,
                PageCodec.nameOf(data, page.path),
            )
        }
    }

    @Test
    fun `a truncated archive opens the pages that survived`() = runTest {
        // `publication-formats` requires opening whatever can be read rather than
        // refusing the publication, and ADR-0008's own reader is what makes
        // forward-scanning recovery possible at all.
        open("truncated.cbz").use { archive ->
            assertTrue((archive as ZipComicArchive).isRecovered)
            // The fixture is 60% of a 12-page archive, so some pages survived and
            // some did not. A bound rather than an exact count: the split depends
            // on DEFLATE output, which differs between zlib builds.
            assertTrue(archive.pages.isNotEmpty())
            assertTrue(archive.pages.size < 12)
            assertTrue(archive.pages.all { it.path.startsWith("page") })
        }
    }

    @Test
    fun `pages recovered from a truncated archive really decode`() = runTest {
        // An index rebuilt by scanning is worthless if the bytes behind it do not
        // come out. Every page the reader claims has to be a page.
        open("truncated.cbz").use { archive ->
            for (page in archive.pages) {
                val data = archive.data(page)
                assertArrayEquals(
                    "${page.path} did not decode to a PNG",
                    byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A),
                    data.copyOfRange(0, 8),
                )
            }
        }
    }

    @Test
    fun `an intact archive is not reported as recovered`() = runTest {
        // Recovery trusts local headers, which ADR-0008 otherwise forbids. A caller
        // has to be able to tell the two apart.
        open("natural-sort.cbz").use { archive ->
            assertFalse((archive as ZipComicArchive).isRecovered)
        }
    }

    @Test
    fun `page bytes decode back to the PNG that was packed`() = runTest {
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
    fun `ComicInfo xml is captured as metadata, not served as a page`() = runTest {
        (open("non-image-entries.cbz") as ZipComicArchive).use { archive ->
            assertEquals(listOf("page1.png", "page2.png"), archive.pages.map { it.path })
            val xml = requireNotNull(archive.comicInfoData).decodeToString()
            assertTrue(xml.contains("Fixture Series"))
        }
    }

    @Test
    fun `reading every page skips nothing in a healthy archive`() = runTest {
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
    fun `a RAR with nothing behind its signature is damaged, not unsupported`() {
        // RAR is readable now, so eight bytes of signature is a damaged file
        // rather than a container StoryArc declines. Naming it as unsupported
        // would tell the user to convert a file that is simply broken.
        val tmp = File.createTempFile("fake", ".cbr")
        try {
            tmp.writeBytes(byteArrayOf(0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00))
            assertThrows(ComicArchiveException.Unreadable::class.java) {
                kotlinx.coroutines.runBlocking { ComicArchiveOpener.open(tmp) }
            }
        } finally {
            tmp.delete()
        }
    }

    @Test
    fun `every container StoryArc refuses is named, never reported generically`() {
        // `publication-formats` forbids a generic parse failure. Someone who
        // hands a 7-Zip comic to a comic reader deserves to be told that.
        for (container in FormatSniffer.Container.entries) {
            assertTrue(container.name, container.displayName.isNotEmpty())
        }
        assertEquals("7-Zip", FormatSniffer.Container.SEVEN_ZIP.displayName)
    }

    @Test
    fun `probing a remote file stays a single small read`() {
        // `network-share` requires opening a 400 MB archive over SMB without
        // transferring it, and sniffing is the first read. What costs money is
        // the round trip, not the byte count — 265 bytes and 8 bytes are the same
        // single SMB read, and 265 is the floor because TAR puts its magic at
        // offset 257. A whole 4 KB page would still be one round trip, so this
        // bound exists to catch a probe that starts scanning the file rather than
        // reading its head.
        assertTrue(FormatSniffer.PROBE_LENGTH <= 512)
        assertTrue(FormatSniffer.PROBE_LENGTH >= TarReader.MAGIC_OFFSET + 5)
    }
}
