package app.storyarc.core.kavita

import app.storyarc.core.model.KavitaCard
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two numbers Kavita sends that mean something, held against Kavita's own tables.
 *
 * `kavita-server` requires the app to display "publication status, age rating" among the
 * metadata the server holds, and both arrive over the wire as bare integers. The table is
 * copied from `Kavita.Models/Entities/Enums/AgeRating.cs` and `PublicationStatus.cs`, so the
 * failure this file exists to catch is a silent one: nothing throws when a number is mapped
 * to the wrong name, and a reader would be shown a rating the server never gave.
 */
class KavitaRatingsTest {

    /** The client's own leniency, so the decode below is the decode production performs. */
    private val json = Json { ignoreUnknownKeys = true }

    private fun metadata(ageRating: Int = 0, publicationStatus: Int = 0) =
        KavitaMetadata(seriesId = 1, ageRating = ageRating, publicationStatus = publicationStatus)

    @Test
    fun `every age rating Kavita defines maps to Kavita's own label`() {
        // The whole table, position by position. A test that checked one case would pass on
        // an enum that had been reordered by one.
        val expected = mapOf(
            -1 to "Not Applicable",
            0 to "Unknown",
            1 to "Rating Pending",
            2 to "Early Childhood",
            3 to "Everyone",
            4 to "G",
            5 to "Everyone 10+",
            6 to "PG",
            7 to "Kids to Adults",
            8 to "Teen",
            9 to "MA15+",
            10 to "Mature 17+",
            11 to "M",
            12 to "R18+",
            13 to "Adults Only 18+",
            14 to "X18+",
        )
        expected.forEach { (number, label) ->
            assertEquals(label, KavitaAgeRating.of(number)?.label)
        }
        assertEquals(expected.size, KavitaAgeRating.entries.size)
    }

    @Test
    fun `a number no version of this app knows is not a rating`() {
        // Kavita has added cases to this enum before. Mapping an unknown number onto the
        // nearest known one would state a rating no server ever gave.
        assertNull(KavitaAgeRating.of(15))
        assertNull(KavitaAgeRating.of(-2))
        assertNull(metadata(ageRating = 15).rating)
    }

    @Test
    fun `Kavita's two non-ratings are not ratings`() {
        // `Unknown` is the default for a series nobody has rated and `Not Applicable` is a
        // profile setting sharing the enum. Drawing either would tell a parent the book had
        // been assessed.
        assertFalse(KavitaAgeRating.UNKNOWN.isStated)
        assertFalse(KavitaAgeRating.NOT_APPLICABLE.isStated)
        assertNull(metadata(ageRating = 0).rating)
        assertNull(metadata(ageRating = -1).rating)

        assertTrue(KavitaAgeRating.EVERYONE.isStated)
        assertEquals(KavitaAgeRating.MATURE_17_PLUS, metadata(ageRating = 10).rating)
    }

    @Test
    fun `every publication status Kavita defines maps to its own case`() {
        val expected = mapOf(
            0 to KavitaPublicationStatus.ONGOING,
            1 to KavitaPublicationStatus.HIATUS,
            2 to KavitaPublicationStatus.COMPLETED,
            3 to KavitaPublicationStatus.CANCELLED,
            4 to KavitaPublicationStatus.ENDED,
        )
        expected.forEach { (number, status) -> assertEquals(status, KavitaPublicationStatus.of(number)) }
        assertEquals(expected.size, KavitaPublicationStatus.entries.size)
    }

    @Test
    fun `an unrecognised status is left unsaid rather than guessed`() {
        assertNull(KavitaPublicationStatus.of(5))
        assertNull(metadata(publicationStatus = 5).status)
        // Zero is a state and not an absence: Kavita's default is that the series is running.
        assertEquals(KavitaPublicationStatus.ONGOING, metadata(publicationStatus = 0).status)
    }

    @Test
    fun `the fields survive the decode the client does`() {
        // The wire shape, not a hand-built value: the two fields are `ageRating` and
        // `publicationStatus` on `/api/Series/metadata`, and a rename either side is exactly
        // the drift `ignoreUnknownKeys` would swallow into a default of zero.
        val decoded = json.decodeFromString(
            KavitaMetadata.serializer(),
            """{"seriesId":3,"ageRating":8,"publicationStatus":2,"releaseYear":2020}""",
        )

        assertEquals(KavitaAgeRating.TEEN, decoded.rating)
        assertEquals(KavitaPublicationStatus.COMPLETED, decoded.status)
    }

    @Test
    fun `a card states the two the same way a live answer does`() {
        // *Reading a downloaded Kavita title offline* is the live path with the card in place
        // of the response, so the two rules have to be the same two rules.
        val card = KavitaCard(
            publicationId = "p1",
            sourceId = "s",
            seriesId = 7,
            chapterId = 1,
            seriesName = "Tidal Reach",
            chapterName = "The Harbour",
            ageRating = 10,
            publicationStatus = 2,
        )
        assertEquals(KavitaAgeRating.MATURE_17_PLUS, card.rating)
        assertEquals(KavitaPublicationStatus.COMPLETED, card.status)
    }

    @Test
    fun `a card that recorded neither number states neither`() {
        // The defaults, which are two different shapes on purpose: zero is Kavita's own
        // `Unknown` rating, and -1 is outside Kavita's status table because zero there is
        // `OnGoing` -- a state a curator chose, which a card must not claim on a server's
        // behalf.
        val bare = KavitaCard(
            publicationId = "p1",
            sourceId = "s",
            seriesId = 7,
            chapterId = 1,
            seriesName = "Tidal Reach",
            chapterName = "The Harbour",
        )
        assertEquals(0, bare.ageRating)
        assertEquals(-1, bare.publicationStatus)
        assertNull(bare.rating)
        assertNull(bare.status)
    }
}
