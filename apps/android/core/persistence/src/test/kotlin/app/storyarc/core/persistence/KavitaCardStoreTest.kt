package app.storyarc.core.persistence

import app.storyarc.core.model.KavitaCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * What a Kavita server said, kept so a download can be read without it.
 *
 * iOS's `KavitaCardStoreTests` makes the same six claims in the same order.
 */
class KavitaCardStoreTest {

    private fun store() = KavitaCardStore(FakePreferences())

    private fun card(
        publication: String,
        source: String = "s",
        series: String = "Tidal Reach",
        chapter: Int = 1,
    ) = KavitaCard(
        publicationId = publication,
        downloadId = "download-$publication",
        sourceId = source,
        libraryId = 3,
        seriesId = 7,
        chapterId = chapter,
        seriesName = series,
        chapterName = "The Harbour",
        summary = "A summary the server holds.",
        people = listOf("Ada Okonkwo"),
        subjects = listOf("Adventure"),
        releaseYear = 1998,
        // Kavita's own numbers: 10 is `Mature 17+` and 2 is `Completed`. Neither is a
        // default, so a field dropped anywhere on the way to disk reads as one that is.
        ageRating = 10,
        publicationStatus = 2,
    )

    @Test
    fun `a card survives a round trip whole`() {
        val store = store()
        store.save(card("p1"))
        val read = store.card("p1")
        assertNotNull(read)
        assertEquals("A summary the server holds.", read!!.summary)
        // The whole chain, because a progress post missing one of the four is refused.
        assertEquals(3, read.libraryId)
        assertEquals("download-p1", read.downloadId)
        assertEquals(listOf("1998", "Ada Okonkwo", "Adventure"), read.facts)
        // The two `kavita-server`'s *Metadata* requirement names that no local file states.
        // Round trip, not field: they are only useful if they come back off the disk.
        assertEquals(10, read.ageRating)
        assertEquals(2, read.publicationStatus)
    }

    @Test
    fun `a second keep of the same publication replaces the first`() {
        val store = store()
        store.save(card("p1", series = "Old name"))
        store.save(card("p1", series = "Tidal Reach"))
        assertEquals(1, store.all().size)
        assertEquals("Tidal Reach", store.card("p1")?.seriesName)
    }

    @Test
    fun `cards are narrowed to one source`() {
        val store = store()
        store.save(card("p1", source = "a"))
        store.save(card("p2", source = "b"))
        assertEquals(listOf("p1"), store.all("a").map { it.publicationId })
    }

    @Test
    fun `removing a publication's card leaves the others`() {
        val store = store()
        store.save(card("p1"))
        store.save(card("p2"))
        store.remove("p1")
        assertEquals(listOf("p2"), store.all().map { it.publicationId })
    }

    @Test
    fun `removing a source takes every card it produced`() {
        // `sources` makes removing a source take its downloads with it, and what was cached
        // about them is part of what it took.
        val store = store()
        store.save(card("p1", source = "a"))
        store.save(card("p2", source = "a"))
        store.save(card("p3", source = "b"))
        store.removeAll("a")
        assertEquals(listOf("p3"), store.all().map { it.publicationId })
    }

    @Test
    fun `a card written before the two numbers existed states neither`() {
        // The bytes an older build left in the preferences, not a re-encoded value. A
        // `@Serializable` property with a default is filled in when the key is missing --
        // and the *values* those defaults carry are the claim: zero is Kavita's `Unknown`
        // rating, which draws no line, and -1 is outside Kavita's status table. Zero would
        // have been `OnGoing`, so a card that fell back to it would tell a reader the series
        // is running on a server's behalf.
        val preferences = FakePreferences()
        preferences.edit().putString(
            "cards",
            """{"p1":{"publicationId":"p1","sourceId":"s","seriesId":7,"chapterId":1,""" +
                """"seriesName":"Tidal Reach","chapterName":"The Harbour","releaseYear":1998}}""",
        ).apply()

        val read = KavitaCardStore(preferences).card("p1")
        assertNotNull(read)
        assertEquals("Tidal Reach", read!!.seriesName)
        assertEquals(0, read.ageRating)
        assertEquals(-1, read.publicationStatus)
    }

    @Test
    fun `a card with no names on it still reads, rather than emptying the cache`() {
        // [KavitaCardStore] decodes every card as one map with a single `runCatching`, so a
        // row kotlinx.serialization refuses takes the reader's whole offline library with it
        // and not two fields. `seriesName` and `chapterName` are defaulted for that reason
        // and no other; iOS's hand-written decoder defaults the same two keys.
        val preferences = FakePreferences()
        preferences.edit().putString(
            "cards",
            """{"p1":{"publicationId":"p1","sourceId":"s","seriesId":7,"chapterId":1},""" +
                """"p2":{"publicationId":"p2","sourceId":"s","seriesId":8,"chapterId":2,""" +
                """"seriesName":"Tidal Reach","chapterName":"The Harbour"}}""",
        ).apply()

        val store = KavitaCardStore(preferences)
        val read = store.card("p1")
        assertNotNull(read)
        assertEquals("", read!!.seriesName)
        assertEquals("", read.chapterName)
        // And the row beside it is still there, which is the whole point of not throwing.
        assertEquals("Tidal Reach", store.card("p2")?.seriesName)
    }
}
