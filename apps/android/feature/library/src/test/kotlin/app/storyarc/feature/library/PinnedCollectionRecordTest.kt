package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.RememberedShelfKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * `close-the-audited-gaps` task 17.10: a pinned server collection is a Home shelf of its own.
 *
 * Two of the three things it rests on had no test: a collection's key carries the collection
 * kind, and its record lists the names of its series. Reverted, either one emptied every pinned
 * collection on Home while every other test stayed green, because the home tests hand the
 * shelf its members rather than reading the record.
 */
class PinnedCollectionRecordTest {

    private val server = KavitaPage(
        "55555555-5555-5555-5555-555555555555",
        "Kavita at home",
        KavitaAddress("http://localhost", "key"),
    )

    @Test
    fun `collection 7 and reading list 7 on one server are two shelves`() {
        val collection = ShelfSync.key(ServerShelf(server, 7, "Arcs", isList = false))
        val list = ShelfSync.key(ServerShelf(server, 7, "Arcs", isList = true))

        assertEquals(RememberedShelfKind.COLLECTION, collection.kind)
        assertEquals(RememberedShelfKind.READING_LIST, list.kind)
        assertNotEquals(collection, list)
    }

    @Test
    fun `a collection records the names of its series, which is what Home filters by`() {
        val series = listOf(KavitaSeries(id = 3, name = "Ashfall"), KavitaSeries(id = 9, name = "Tidal Reach"))

        assertEquals(listOf("Ashfall", "Tidal Reach"), ShelfSync.collectionMembers(series))
    }
}
