package app.storyarc.core.persistence

import app.storyarc.core.model.KavitaCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

/**
 * What a Kavita server said, kept so a download can be read without it.
 *
 * iOS's `KavitaCardStoreTests` makes the same five claims in the same order.
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
        assertEquals(listOf("1998", "Ada Okonkwo", "Adventure"), read.facts)
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
}
