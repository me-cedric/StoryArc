package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Where a new shelf can be kept, and what the reader is told before it exists.
 *
 * `collections-and-reading-lists`: a new shelf "is stored locally by default, or on a server
 * if the user chooses one that supports collections", and "the storage location is stated at
 * creation, not discovered later".
 *
 * The second half is what makes the first half matter. A server answers the collection
 * question and the reading-list question separately, so offering a reading list to a server
 * that only holds collections would take the reader's name and their confirmation and fail
 * afterwards -- the storage location discovered later, which is the thing the scenario forbids.
 *
 * [ShelfCreationDialog] reads both answers from here, and the dialogue itself is not composed
 * in a host test: an `OutlinedTextField` inside an `AlertDialog` never settles under
 * Robolectric, so the run fills the heap with text layouts instead of failing. iOS has the
 * same gap, because a SwiftUI alert cannot be asked what it drew. `ShelfCreationTests` there
 * asserts the same seven cases.
 */
class ShelfCreationTest {

    // MARK: - Fixtures

    private fun page(name: String) = KavitaPage(
        id = name,
        title = name,
        address = KavitaAddress(base = "https://$name.example", apiKey = "k"),
    )

    /** A server that holds collections, one that holds reading lists, and one that holds both. */
    private val collectionCapable = listOf(page("collections"), page("both"))
    private val listCapable = listOf(page("lists"), page("both"))

    private val nothing = emptyList<KavitaPage>()

    // MARK: - Which servers are offered

    @Test
    fun `a reading list is offered only the servers that hold reading lists`() {
        val draft = ShelfDraft.of(isList = true, collectionCapable, listCapable)

        assertEquals(listOf("lists", "both"), draft.servers.map { it.title })
    }

    @Test
    fun `a collection is offered only the servers that hold collections`() {
        val draft = ShelfDraft.of(isList = false, collectionCapable, listCapable)

        assertEquals(listOf("collections", "both"), draft.servers.map { it.title })
    }

    @Test
    fun `the two kinds are offered different servers, which is the point of asking twice`() {
        // Without this the two cases above would both pass against one shared list.
        val lists = ShelfDraft.of(true, collectionCapable, listCapable).servers.map { it.title }
        val collections =
            ShelfDraft.of(false, collectionCapable, listCapable).servers.map { it.title }

        assertNotEquals(collections, lists)
    }

    // MARK: - What the reader is told

    @Test
    fun `with no server to offer, the shelf is stated as kept on this device`() {
        assertTrue(ShelfDraft.of(false, nothing, nothing).isKeptOnThisDevice)
    }

    @Test
    fun `with a server to offer, confirming is a choice rather than the only place`() {
        assertFalse(ShelfDraft.of(false, collectionCapable, listCapable).isKeptOnThisDevice)
    }

    @Test
    fun `a kind with no capable server says so while the other kind has one`() {
        // The reader making a reading list on a collections-only server is told it stays here,
        // because it does. The same app, the same moment, the other kind: a choice.
        assertTrue(ShelfDraft.of(true, collectionCapable, nothing).isKeptOnThisDevice)
        assertFalse(ShelfDraft.of(false, collectionCapable, nothing).isKeptOnThisDevice)
    }
}
