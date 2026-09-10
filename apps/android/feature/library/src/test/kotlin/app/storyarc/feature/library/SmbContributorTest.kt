package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.smb.SmbEntry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What one file on a share looks like as a row.
 *
 * A share is the one source that cannot be asked -- it is a filesystem, walked. Two things
 * follow, and both are asserted here: the row is identified by its path, as a scanned file
 * is, so a share's copy and a downloaded copy fold together without a server identifier;
 * and the metadata is the filename's and says so, because reading the file's own would mean
 * fetching the archive.
 */
class SmbContributorTest {

    private val source = UUID.randomUUID()

    private fun row(name: String, folder: String = "/comics/Lantern Green") =
        SmbContributor.publication(
            source,
            SmbEntry(name = name, path = "$folder/$name", isDirectory = false, length = 1),
            folder = folder,
        )

    @Test
    fun `a file is identified by its path, as a scanned file is`() {
        val publication = row("Lantern Green 043.cbz")!!

        assertEquals("/comics/Lantern Green/Lantern Green 043.cbz", publication.identity.normalizedPath)
        assertNull(publication.identity.serverIdentifier)
        assertEquals(source, publication.sourceId)
    }

    @Test
    fun `the filename is what the row knows, and the row says so`() {
        val publication = row("Lantern Green 043.cbz")!!

        assertEquals(MetadataOrigin.INFERRED, publication.origin)
        assertEquals("Lantern Green 043", publication.displayTitle)
        assertEquals("43", publication.number)
    }

    @Test
    fun `the folder names the series when the filename does not`() {
        // A share's folders are how a reader has already organised it.
        assertEquals("Lantern Green", row("043.cbz")?.series)
    }

    @Test
    fun `a file this app cannot open is not a row`() {
        assertNull(row("notes.txt"))
        assertNull(row("cover.jpg"))
        assertNull(row("Lantern Green 043"))
    }

    @Test
    fun `each extension files under a format the filter can show`() {
        assertEquals(PublicationFormat.CBZ, row("a.cbz")?.format)
        assertEquals(PublicationFormat.CBR, row("a.CBR")?.format)
        assertEquals(PublicationFormat.CB7, row("a.cb7")?.format)
        assertEquals(PublicationFormat.CBT, row("a.cbt")?.format)
        assertEquals(PublicationFormat.EPUB, row("a.epub")?.format)
        assertEquals(PublicationFormat.PDF, row("a.pdf")?.format)
    }

    @Test
    fun `the walk is bounded, and the bounds are stated rather than implied`() {
        // A share may hold a hundred thousand files. The numbers are the contract: what is
        // not reached stays in the browser and in search.
        assertEquals(200, SmbContributor.FIRST_SLICE)
        assertEquals(40, SmbContributor.MAX_FOLDERS)
    }
}
