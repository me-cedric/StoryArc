package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.StreamingCapability
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbEntry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What one file on a share looks like as a row.
 *
 * A share is the one source that cannot be asked -- it is a filesystem, walked. Three things
 * follow, and all three are asserted here: the row is identified by the share's own `smb://`
 * address for the file, not the bare path `SmbClient.list` returns -- a location that is not
 * a real address reads as local, so the shelf used to count a row nobody had downloaded as
 * already on the device, and opening it handed the reader a path that existed nowhere on the
 * filesystem; a share's copy and a downloaded copy still fold together, because the address
 * is still one identity per file; and the metadata is the filename's and says so, because
 * reading the file's own would mean fetching the archive.
 */
class SmbContributorTest {

    private val source = UUID.randomUUID()
    private val address = SmbAddress(host = "nas.local", share = "Comics")

    private fun row(name: String, folder: String = "comics/Lantern Green") =
        SmbContributor.publication(
            source,
            SmbEntry(name = name, path = "$folder/$name", isDirectory = false, length = 1),
            address,
            folder = folder,
        )

    @Test
    fun `a file is identified by the share's own address for it, not its bare path`() {
        val publication = row("Lantern Green 043.cbz")!!

        assertEquals(
            "smb://nas.local/Comics/comics/Lantern Green/Lantern Green 043.cbz",
            publication.identity.normalizedPath,
        )
        // `PublicationAccess.isRemote` matches a location by its scheme prefix -- a plain
        // path answers false and the shelf reads the row as already on the device.
        assertTrue(publication.identity.normalizedPath!!.startsWith("smb://"))
        assertNull(publication.identity.serverIdentifier)
        assertEquals(source, publication.sourceId)
    }

    @Test
    fun `a row states the size the share already stated, for free`() {
        // `publication-formats` asks the download offer on the publication page to state
        // the size, and a directory entry already carries its own length -- so the share
        // walk hands it over rather than leaving the reader to guess.
        val publication = SmbContributor.publication(
            source,
            SmbEntry(
                name = "Lantern Green 043.cbz",
                path = "comics/Lantern Green/Lantern Green 043.cbz",
                isDirectory = false,
                length = 400_000_000L,
            ),
            address,
            folder = "comics/Lantern Green",
        )!!

        assertEquals(400_000_000L, publication.fileSize)
    }

    @Test
    fun `a row under a configured root opens through the reader's own reading of its address`() {
        // `entry.path` is relative to the share and so repeats the root the reader picked.
        // The opener strips the source's address, root and all, and hands the share the
        // rest -- so the row's address has to state the root in both places, the way the
        // share browser always has, or the share is asked for `Comics/x.cbz` at its top.
        val entry = SmbEntry(
            name = "x.cbz",
            path = "Books/Comics/x.cbz",
            isDirectory = false,
            length = 1,
        )
        val configured = address.copy(path = "Books")

        val publication = SmbContributor.publication(source, entry, configured, folder = "Books/Comics")!!

        assertEquals(
            entry.path,
            SmbLocator.inside(publication.identity.normalizedPath!!, configured),
        )
        assertEquals(SmbLocator.entry(entry.path, configured), publication.identity.normalizedPath)
    }

    @Test
    fun `an address is inside a share only past its own name`() {
        val configured = address.copy(path = "Books")
        assertEquals("Books/x.cbz", SmbLocator.inside("smb://nas.local/Comics/Books/Books/x.cbz", configured))
        assertEquals("", SmbLocator.inside("smb://nas.local/Comics/Books", configured))
        assertNull(SmbLocator.inside("smb://nas.local/Comics/BooksExtra/x.cbz", configured))
        assertNull(SmbLocator.inside("smb://other.local/Comics/Books/x.cbz", configured))
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
    fun `a cb7 row is refused by name, before any tap`() {
        // Known from the name alone: no header read decides a CB7 cannot open.
        val cb7 = row("Lantern Green 043.cb7")!!
        assertEquals(StreamingCapability.REFUSED, cb7.streaming)
        assertFalse(cb7.isOpenable)

        val cbz = row("Lantern Green 043.cbz")!!
        assertEquals(StreamingCapability.STREAMS, cbz.streaming)
        assertTrue(cbz.isOpenable)
    }

    @Test
    fun `the walk is bounded, and the bounds are stated rather than implied`() {
        // A share may hold a hundred thousand files. The numbers are the contract: what is
        // not reached stays in the browser and in search.
        assertEquals(200, SmbContributor.FIRST_SLICE)
        assertEquals(40, SmbContributor.MAX_FOLDERS)
    }
}
