package app.storyarc.core.persistence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The two stores a Kavita chapter's address can live in, and which one a write trusts.
 *
 * `kavita-server` task 12.1: a row the library merely lists needs an origin too, but
 * [KavitaProgressStore.origin] must keep meaning "this device opened it" -- that is what
 * [KavitaProgressStore.publicationForChapter] answers from, and a catalogued note must never
 * make that answer yes. iOS's `KavitaContributorCatalogOriginTests` makes the same claims.
 */
class KavitaCatalogOriginTest {

    private fun store() = KavitaProgressStore(FakePreferences())

    private fun origin(chapterId: Int, pages: Int) = KavitaOrigin(
        sourceId = "server-a",
        libraryId = 7,
        seriesId = 312,
        volumeId = 55,
        chapterId = chapterId,
        pages = pages,
    )

    @Test
    fun `a catalogued origin resolves, but is not mistaken for an opened one`() {
        val store = store()
        store.rememberCatalog(mapOf("row-1" to origin(3103, pages = 22)))

        assertNull(store.origin("row-1"))
        assertEquals(3103, store.catalogOrigin("row-1")?.chapterId)
        assertEquals(3103, store.resolvedOrigin("row-1")?.chapterId)
        // "Has this device opened it" must stay false for a row only ever catalogued.
        assertNull(store.publicationForChapter(3103))
    }

    @Test
    fun `an opened origin outranks a catalogued one`() {
        val store = store()
        // The catalogued note carries pages 22. The opened note below deliberately
        // disagrees -- pages 99 -- so the two are distinguishable: a resolver that picked
        // the wrong one would still answer *a* value, and only a mismatched field proves
        // which one it picked.
        store.rememberCatalog(mapOf("row-1" to origin(3103, pages = 22)))
        store.remember("row-1", origin(3103, pages = 99))

        assertEquals(99, store.resolvedOrigin("row-1")?.pages)
        assertEquals("row-1", store.publicationForChapter(3103))
    }

    @Test
    fun `rememberCatalog does nothing for an empty batch`() {
        val store = store()
        store.rememberCatalog(emptyMap())

        assertNull(store.catalogOrigin("row-1"))
    }
}
