package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PublicationFormat
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What one chapter of a server's library looks like as a row.
 *
 * `library-browsing` asks for "publications from every configured source" with "nothing on
 * the shelf [stating] which source a publication came from", so the row a server supplies
 * has to be the same kind of thing a scanned file is -- a title, a series, a number, a
 * format the filter can show -- and differ only in having nothing on disk.
 */
class KavitaContributorTest {

    private val source = UUID.randomUUID()

    private fun row(
        series: KavitaSeries = KavitaSeries(id = 312, name = "Lantern Green", format = 1),
        chapter: KavitaChapter = KavitaChapter(id = 3103, number = "43", title = "Issue #43", pages = 22),
    ) = KavitaContributor.publication(source, series, chapter)

    @Test
    fun `a chapter is identified by the server, not by a path`() {
        val publication = row()

        assertEquals(source, publication.identity.serverIdentifier?.sourceId)
        assertEquals("chapter:3103", publication.identity.serverIdentifier?.remoteId)
        // The whole of what makes it remote: nothing is on disk, so the cover resolver and
        // the availability axis both read it as needing its source.
        assertNull(publication.identity.normalizedPath)
    }

    @Test
    fun `it carries what a row is drawn from`() {
        val publication = row()

        assertEquals("Issue #43", publication.displayTitle)
        assertEquals("Lantern Green", publication.series)
        assertEquals("43", publication.number)
        assertEquals(22, publication.pageCount)
        assertEquals(source, publication.sourceId)
    }

    @Test
    fun `a chapter Kavita gave no number is called by its series`() {
        // Kavita writes -100000 for a chapter with no number -- a collected edition, a
        // volume with one part. The library drew shelves of cells titled "-100000".
        val publication = row(chapter = KavitaChapter(id = 1, number = "-100000", title = ""))

        assertEquals("Lantern Green", publication.displayTitle)
        // And the sentinel is not kept as the number either. It was, and `#<number>` is
        // drawn on its own beneath the title -- so the row read "Lantern Green" and the
        // line under it read "Lantern Green #-100000", which is what a reader reported.
        assertNull(publication.number)
    }

    @Test
    fun `a chapter with a real title keeps it`() {
        assertEquals("Issue #43", row().displayTitle)
    }

    @Test
    fun `a numbered chapter is named for its series and its number, not the number alone`() {
        // A shelf of cells headed "43" names nothing, and the caption under one then
        // carried the only words on the cell. `<series> #<number>` is the house format --
        // what `seriesLine` composes, and what a filename-derived title already looks
        // like -- so a server's issue and a scanned one read the same.
        val publication = row(chapter = KavitaChapter(id = 1, number = "7", title = ""))

        assertEquals("Lantern Green #7", publication.displayTitle)
        assertEquals("7", publication.number)
    }

    @Test
    fun `the server owns the metadata, so a downloaded file does not overwrite it`() {
        assertEquals(MetadataOrigin.AUTHORITATIVE, row().origin)
    }

    @Test
    fun `each of Kavita's formats files under one this app can filter`() {
        assertEquals(PublicationFormat.IMAGE_FOLDER, row(seriesOf(0)).format)
        assertEquals(PublicationFormat.EPUB, row(seriesOf(3)).format)
        assertEquals(PublicationFormat.PDF, row(seriesOf(4)).format)
    }

    @Test
    fun `an archive files as CBZ, which is a guess and is the documented one`() {
        // Kavita says "archive" and not which archive, so a CBR on a server is listed as a
        // CBZ until it is downloaded. Pinned so the guess is visible rather than folklore.
        assertEquals(PublicationFormat.CBZ, row(seriesOf(1)).format)
        assertEquals(PublicationFormat.CBZ, row(seriesOf(2)).format)
    }

    @Test
    fun `two rows from one server are one row when they are the same chapter`() {
        val first = row()
        val second = row()

        assertTrue(first.identity.matches(second.identity))
    }

    private fun seriesOf(format: Int) = KavitaSeries(id = 1, name = "Lantern Green", format = format)
}
