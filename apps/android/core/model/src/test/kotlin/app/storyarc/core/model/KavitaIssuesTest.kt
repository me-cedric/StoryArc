package app.storyarc.core.model

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The issues of a series the server matched, joined on this device.
 *
 * `kavita-server`: a search of a Kavita source lists "the issues of every matched series
 * ... joined on the device from the publications that source has already contributed to the
 * library". These are the cases the join has to get right, in the order iOS's
 * `KavitaIssuesTests` asserts them.
 */
class KavitaIssuesTest {
    private val source: UUID = UUID.randomUUID()

    private fun issue(
        series: String,
        chapterId: Int,
        title: String = "$series #$chapterId",
    ) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = source,
                remoteId = "chapter:$chapterId",
            ),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = source,
    )

    private val greenLantern = KavitaHit(KavitaHit.Kind.SERIES, "Green Lantern (2005)", 7)

    @Test
    fun `a matched series lists the issues the library holds`() {
        val joined = KavitaIssues.joined(
            listOf(greenLantern),
            listOf(issue("Green Lantern (2005)", 11), issue("Green Lantern (2005)", 12)),
        )
        val chapters = joined.filter { it.kind == KavitaHit.Kind.CHAPTER }
        assertEquals(listOf("Green Lantern (2005) #11", "Green Lantern (2005) #12"), chapters.map { it.title })
        assertEquals(listOf(11, 12), chapters.map { it.chapterId })
    }

    @Test
    fun `the series the server matched is kept`() {
        val joined = KavitaIssues.joined(listOf(greenLantern), listOf(issue("Green Lantern (2005)", 11)))
        assertEquals(listOf(greenLantern), joined.filter { it.kind == KavitaHit.Kind.SERIES })
    }

    @Test
    fun `a joined issue opens its series`() {
        val joined = KavitaIssues.joined(listOf(greenLantern), listOf(issue("Green Lantern (2005)", 11)))
        val chapter = joined.first { it.kind == KavitaHit.Kind.CHAPTER }
        assertEquals(7, chapter.seriesId)
        assertTrue(chapter.isOpenable)
        // Nothing on this device holds the file: the row leads to the server's series.
        assertEquals(null, chapter.downloadId)
    }

    @Test
    fun `a chapter the server already sent is not drawn twice`() {
        // The two producers name one chapter differently -- the server answers with its
        // own display name, the library with the title `KavitaNaming` wrote -- so the hit
        // ids differ and only kind, series and chapter tell them apart. A keyed list
        // refuses two rows with one key.
        val fromServer = KavitaHit(KavitaHit.Kind.CHAPTER, "Rebirth", 7, chapterId = 11)
        val joined = KavitaIssues.joined(
            listOf(greenLantern, fromServer),
            listOf(issue("Green Lantern (2005)", 11), issue("Green Lantern (2005)", 12)),
        )
        assertEquals(listOf(11, 12), joined.filter { it.kind == KavitaHit.Kind.CHAPTER }.map { it.chapterId })
        assertEquals("Rebirth", joined.first { it.chapterId == 11 }.title)
        assertEquals(joined.map { it.id }.distinct(), joined.map { it.id })
    }

    @Test
    fun `a publication of another series contributes nothing`() {
        val joined = KavitaIssues.joined(listOf(greenLantern), listOf(issue("Green Arrow (2001)", 11)))
        assertEquals(emptyList<KavitaHit>(), joined.filter { it.kind == KavitaHit.Kind.CHAPTER })
    }

    @Test
    fun `a publication with no chapter of its own contributes nothing`() {
        // A row from a folder or from a catalogue carries no Kavita chapter, so there is
        // nothing to open and nothing to key a row on.
        val local = Publication(
            identity = PublicationIdentity(normalizedPath = "/books/green-lantern.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "Green Lantern (2005) #11",
            series = "Green Lantern (2005)",
            origin = MetadataOrigin.EMBEDDED,
        )
        assertEquals(listOf(greenLantern), KavitaIssues.joined(listOf(greenLantern), listOf(local)))
    }

    @Test
    fun `a person and a subject bring no issues`() {
        val person = KavitaHit(KavitaHit.Kind.PERSON, "Green Lantern (2005)")
        val joined = KavitaIssues.joined(listOf(person), listOf(issue("Green Lantern (2005)", 11)))
        assertEquals(listOf(person), joined)
    }

    @Test
    fun `nothing matched means nothing joined`() {
        assertEquals(emptyList<KavitaHit>(), KavitaIssues.joined(emptyList(), listOf(issue("Green Lantern (2005)", 11))))
    }
}
