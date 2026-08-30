package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Searching a Kavita source with the server away.
 *
 * `kavita-server`: with the server unreachable "the search falls back to the local cache and
 * states that results are limited to cached content". These are the cases the fallback has to
 * get right, in the order iOS's `KavitaFindTests` asserts them.
 */
class KavitaFindTest {
    private fun card(
        publication: String,
        series: String,
        seriesId: Int = 1,
        chapter: String = "1",
        people: List<String> = emptyList(),
        subjects: List<String> = emptyList(),
    ) = KavitaCard(
        publicationId = publication,
        downloadId = "download-$publication",
        sourceId = "s",
        seriesId = seriesId,
        chapterId = 1,
        seriesName = series,
        chapterName = chapter,
        people = people,
        subjects = subjects,
    )

    /** A publication indexed from the file, with the values a `ComicInfo.xml` would carry. */
    private fun fromFile() = Publication(
        identity = PublicationIdentity(normalizedPath = "/downloads/p1/file.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "File title",
        series = "File series",
        authors = listOf("File author"),
        year = 1970,
        summary = "What the file says.",
        tags = listOf("file-tag"),
        origin = MetadataOrigin.EMBEDDED,
        pageCount = 24,
    )

    @Test
    fun `the server's values replace the file's`() {
        // `kavita-server`: "the app displays Kavita's values, because the server is the
        // curated source" -- and the same values again when the server is unreachable and
        // this card is all that is left of it.
        val described = card("p1", "Tidal Reach").appliedTo(fromFile())
        assertEquals("Tidal Reach", described.series)
        assertEquals("1", described.displayTitle)
        assertEquals(MetadataOrigin.AUTHORITATIVE, described.origin)
    }

    @Test
    fun `a field the card is silent about keeps what the file said`() {
        // The server having no summary is not the server saying there is none.
        val bare = KavitaCard(
            publicationId = "p1",
            sourceId = "s",
            seriesId = 7,
            chapterId = 1,
            seriesName = "Tidal Reach",
            chapterName = "The Harbour",
        )
        val described = bare.appliedTo(fromFile())
        assertEquals("What the file says.", described.summary)
        assertEquals(listOf("File author"), described.authors)
        assertEquals(1970, described.year)
        assertEquals(listOf("file-tag"), described.tags)
    }

    @Test
    fun `what the file alone knows survives the overlay`() {
        // The card describes a publication; it does not describe the archive. A page count or
        // a cover path replaced from a card would be the server answering a question it was
        // never asked.
        val described = card("p1", "Tidal Reach").appliedTo(fromFile())
        assertEquals(24, described.pageCount)
        assertEquals(fromFile().format, described.format)
        assertEquals(fromFile().id, described.id)
    }

    @Test
    fun `an empty query asks for nothing`() {
        assertNull(KavitaFind.term(""))
    }

    @Test
    fun `a query of only spaces asks for nothing`() {
        // A server asked for whitespace answers with its whole library, which reads as a
        // search that matched everything.
        assertNull(KavitaFind.term("   "))
        assertTrue(KavitaFind.inCache("  ", listOf(card("a", "Tidal Reach"))).isEmpty())
    }

    @Test
    fun `a series name match is a series hit`() {
        val hits = KavitaFind.inCache("tidal", listOf(card("a", "Tidal Reach", seriesId = 7)))
        assertEquals(listOf(KavitaHit(KavitaHit.Kind.SERIES, "Tidal Reach", 7, "download-a")), hits)
    }

    @Test
    fun `a chapter name match is a chapter hit`() {
        val hits = KavitaFind.inCache(
            "harbour",
            listOf(card("a", "Tidal Reach", seriesId = 7, chapter = "The Harbour")),
        )
        assertEquals(listOf(KavitaHit(KavitaHit.Kind.CHAPTER, "The Harbour", 7, "download-a")), hits)
    }

    @Test
    fun `matching ignores case`() {
        assertEquals(1, KavitaFind.inCache("TIDAL", listOf(card("a", "Tidal Reach"))).size)
    }

    @Test
    fun `a person match is named after the person, not the series`() {
        val hits = KavitaFind.inCache(
            "okonkwo",
            listOf(card("a", "Tidal Reach", people = listOf("Ada Okonkwo"))),
        )
        assertEquals(listOf(KavitaHit(KavitaHit.Kind.PERSON, "Ada Okonkwo")), hits)
        // Nowhere to go: Kavita answers with the name alone.
        assertFalse(hits.first().isOpenable)
    }

    @Test
    fun `a genre or a tag match is one kind of hit, not two`() {
        val hits = KavitaFind.inCache(
            "horror",
            listOf(card("a", "Tidal Reach", subjects = listOf("Horror", "Cosmic Horror"))),
        )
        assertEquals(listOf(KavitaHit.Kind.SUBJECT, KavitaHit.Kind.SUBJECT), hits.map { it.kind })
        assertEquals(listOf("Horror", "Cosmic Horror"), hits.map { it.title })
    }

    @Test
    fun `one card matching two ways yields one hit of each kind`() {
        val hits = KavitaFind.inCache(
            "reach",
            listOf(card("a", "Tidal Reach", seriesId = 7, chapter = "Reach for it")),
        )
        assertEquals(listOf(KavitaHit.Kind.SERIES, KavitaHit.Kind.CHAPTER), hits.map { it.kind })
    }

    @Test
    fun `two chapters of one series are one series row`() {
        val hits = KavitaFind.inCache(
            "tidal",
            listOf(
                card("a", "Tidal Reach", seriesId = 7, chapter = "1"),
                card("b", "Tidal Reach", seriesId = 7, chapter = "2"),
            ),
        )
        assertEquals(1, hits.size)
    }

    @Test
    fun `a cached row names the download it opens, not the publication it describes`() {
        // Offline a row that cannot be opened is a row that is only there to disappoint -- and
        // the two keys are different, which is what made the row inert when it was the
        // publication's.
        val hits = KavitaFind.inCache("tidal", listOf(card("p1", "Tidal Reach")))
        assertEquals("download-p1", hits.first().downloadId)
    }

    @Test
    fun `a card matching nothing is not a result`() {
        assertTrue(KavitaFind.inCache("zzz", listOf(card("a", "Tidal Reach"))).isEmpty())
    }

    @Test
    fun `headings come back in the spec's own order, and an empty one is left out`() {
        val hits = KavitaFind.inCache(
            "a",
            listOf(
                card("a", "Tidal Reach", seriesId = 7, chapter = "Harbour", people = listOf("Ada")),
            ),
        )
        assertEquals(
            listOf(KavitaHit.Kind.SERIES, KavitaHit.Kind.CHAPTER, KavitaHit.Kind.PERSON),
            KavitaFind.grouped(hits).map { it.first },
        )
    }
}
