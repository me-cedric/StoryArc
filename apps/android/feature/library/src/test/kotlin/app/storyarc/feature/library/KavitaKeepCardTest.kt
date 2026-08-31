package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaMetadata
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.kavita.rating
import app.storyarc.core.kavita.status
import app.storyarc.core.model.KavitaCard
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.kavita.KavitaAgeRating
import app.storyarc.core.kavita.KavitaPublicationStatus
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a keep writes down, which is the whole of *Reading a downloaded Kavita title offline*.
 *
 * **These two lines are the feature and nothing was standing behind them.** [KavitaCard]
 * carries `ageRating` and `publicationStatus`; the card store round-trips them; both tables
 * map them; `KavitaCardFacts` draws them. Every one of those is asserted from a card a test
 * built by hand -- so `KavitaKeep.card` could be changed to write "the server said nothing"
 * for every keep, every kept chapter would draw neither line on either platform, and every
 * Android suite and the whole iOS suite would still pass.
 *
 * This is the one seam where the server's answer becomes the card. iOS's `KavitaKeepCardTests`
 * makes the same three claims.
 *
 * The metadata is decoded from the wire rather than built, because the interesting absences
 * are wire-shaped: `/api/Series/metadata` answering without `publicationStatus` is what Kavita
 * does for a series that has none, and a status read as zero there is `OnGoing`.
 */
class KavitaKeepCardTest {

    /** The client's own leniency, so the decode below is the decode production performs. */
    private val json = Json { ignoreUnknownKeys = true }

    private fun metadata(wire: String) = json.decodeFromString(KavitaMetadata.serializer(), wire)

    private fun card(metadata: KavitaMetadata?) = KavitaKeep.card(
        publicationId = "p1",
        downloadId = "kavita:kavita-1:1",
        chapter = KavitaChapter(id = 1, number = "1", title = "The Harbour", pages = 8),
        series = KavitaSeries(id = 7, name = "Tidal Reach", libraryId = 3),
        metadata = metadata,
        origin = KavitaOrigin(
            sourceId = "kavita-1",
            libraryId = 3,
            seriesId = 7,
            volumeId = 700,
            chapterId = 1,
        ),
    )

    @Test
    fun `a keep writes down the rating and the status the server stated`() {
        // Kavita's own numbers: 10 is `Mature 17+` and 2 is `Completed`.
        val kept = card(
            metadata("""{"seriesId":7,"ageRating":10,"publicationStatus":2,"releaseYear":2020}"""),
        )

        assertEquals(10, kept.ageRating)
        assertEquals(2, kept.publicationStatus)
        // Read back through the same two rules the live answer gets, because that is what the
        // page asks the card for.
        assertEquals(KavitaAgeRating.MATURE_17_PLUS, kept.rating)
        assertEquals(KavitaPublicationStatus.COMPLETED, kept.status)
        // And the five that do have somewhere to go still go there.
        assertEquals(2020, kept.releaseYear)
    }

    @Test
    fun `a keep from an answer that stated neither writes down neither`() {
        // The ordinary case: Kavita omits what a series does not have. The two absences are
        // different shapes because Kavita's two enums are -- zero is its own `Unknown` rating
        // and its `OnGoing` status -- so an absent status has to leave the table entirely.
        val kept = card(metadata("""{"seriesId":7,"releaseYear":2020}"""))

        assertEquals(0, kept.ageRating)
        assertEquals(-1, kept.publicationStatus)
        assertNull(kept.rating)
        assertNull(kept.status)
    }

    @Test
    fun `a keep from a server that answered nothing at all writes down neither`() {
        // The metadata is null when the metadata call failed. A card with a name and no
        // description is better than no card, and it must still not state a status.
        val kept = card(null)

        assertEquals(0, kept.ageRating)
        assertEquals(-1, kept.publicationStatus)
        assertNull(kept.status)
    }
}
