package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaReadingListItem
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.RememberedShelf
import app.storyarc.core.model.RememberedShelfKind
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.Shelves
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The two shelves the home surface lists the reader's curation on.
 *
 * `collections-and-reading-lists`, *Shelves on the home surface*. Every claim here is one the
 * assembly can be asked about without a screen: which half a shelf lands in, what a card says,
 * which shelves are left out, and that no answer changes when a source goes away.
 *
 * Case for case with iOS's `HomeShelfListingTests`.
 */
class HomeShelfListingTest {

    private val serverId: UUID = UUID.fromString("6f1a4a8e-0000-4000-8000-000000000001")

    private fun issue(name: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$name.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = name,
        origin = MetadataOrigin.EMBEDDED,
    )

    private val library = listOf(issue("one"), issue("two"), issue("three"), issue("four"))

    private fun collection(name: String, members: Int = 0) = PublicationCollection(
        name = name,
        members = library.take(members).map { it.id }.toSet(),
    )

    private fun list(name: String, entries: Int = 0) = ReadingList(
        name = name,
        entries = library.take(entries).map { it.id },
    )

    @Test
    fun `a collection lands on the collections shelf and a list on its own`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(collection("Image")), lists = listOf(list("Crisis"))),
            publications = library,
        )

        assertEquals(listOf("Image"), listing.collections.map { it.name })
        assertEquals(listOf("Crisis"), listing.lists.map { it.name })
        assertFalse(listing.isEmpty)
    }

    @Test
    fun `neither half holds anything for a reader with no shelves`() {
        val listing = HomeShelfIndex.assemble(shelves = Shelves(), publications = library)

        assertTrue(listing.isEmpty)
        assertTrue(listing.collections.isEmpty())
        assertTrue(listing.lists.isEmpty())
    }

    @Test
    fun `one kind with nothing in it leaves the other alone`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(collection("Image", members = 2))),
            publications = library,
        )

        assertEquals(1, listing.collections.size)
        assertTrue(listing.lists.isEmpty())
        assertFalse(listing.isEmpty)
    }

    @Test
    fun `a reading list has a position and a collection has none`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(
                collections = listOf(collection("Image", members = 4)),
                lists = listOf(list("Crisis", entries = 4)),
            ),
            publications = library,
            finished = setOf(library[0].id, library[1].id),
        )

        assertNull(listing.collections.single().fraction)
        assertNull(listing.collections.single().finished)
        assertEquals(0.5f, listing.lists.single().fraction!!, 0.0001f)
    }

    @Test
    fun `a shelf stands on the first four covers it holds`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(collection("Image", members = 4))),
            publications = library,
        )

        assertEquals(4, listing.collections.single().tiles.size)
    }

    @Test
    fun `a shelf with nothing in it has no tiles and still appears`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(collection("Empty"))),
            publications = library,
        )

        val card = listing.collections.single()
        assertEquals("Empty", card.name)
        assertEquals(0, card.count)
        assertTrue(card.tiles.isEmpty())
    }

    @Test
    fun `a remembered shelf is listed and labelled with its source`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(),
            publications = library,
            remembered = listOf(
                RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "Marvel"),
                RememberedShelf(RememberedShelfKind.READING_LIST, serverId, 9, "Crisis, in order"),
            ),
            openableSources = mapOf(serverId to "Kavita at home"),
        )

        assertEquals(listOf("Marvel"), listing.collections.map { it.name })
        assertEquals(listOf("Crisis, in order"), listing.lists.map { it.name })
        assertEquals("Kavita at home", listing.collections.single().sourceName)
    }

    @Test
    fun `a remembered shelf states no count, because this device does not know one`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(),
            publications = library,
            remembered = listOf(RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "Marvel")),
            openableSources = mapOf(serverId to "Kavita at home"),
        )

        assertNull(listing.collections.single().count)
    }

    @Test
    fun `a remembered shelf draws the count and finished position it has cached`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(),
            publications = library,
            remembered = listOf(
                RememberedShelf(
                    RememberedShelfKind.READING_LIST, serverId, 9, "Crisis, in order",
                    count = 12, finished = 5,
                ),
            ),
            openableSources = mapOf(serverId to "Kavita at home"),
        )

        assertEquals(12, listing.lists.single().count)
        assertEquals(5, listing.lists.single().finished)
    }

    @Test
    fun `a remembered shelf whose source has gone is left out`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(collection("Mine"))),
            publications = library,
            remembered = listOf(RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "Marvel")),
            openableSources = emptyMap(),
        )

        assertEquals(listOf("Mine"), listing.collections.map { it.name })
    }

    @Test
    fun `the reader's own shelves lead a half, and pinned ones lead them`() {
        val first = collection("First")
        val second = collection("Second")
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(first, second)),
            publications = library,
            remembered = listOf(RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "Marvel")),
            openableSources = mapOf(serverId to "Kavita at home"),
            pinned = PinnedShelves().toggling(ShelfPin.Collection(second.id)),
        )

        assertEquals(listOf("Second", "First", "Marvel"), listing.collections.map { it.name })
    }

    @Test
    fun `a pinned server shelf leads the half, ahead of the reader's own unpinned ones`() {
        // `collections-and-reading-lists`: a server's shelf is "the same kind of object as
        // locally created ones", so `home-screen`'s "ahead of the unpinned ones" reaches
        // across the join. It used to stop at it -- every server shelf sat behind every local
        // one, whatever the reader pinned.
        val marvel = RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "Marvel")
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(collections = listOf(collection("First"), collection("Second"))),
            publications = library,
            remembered = listOf(marvel),
            openableSources = mapOf(serverId to "Kavita at home"),
            pinned = PinnedShelves().toggling(marvel.pin),
        )

        assertEquals(listOf("Marvel", "First", "Second"), listing.collections.map { it.name })
    }

    @Test
    fun `every card's key is its own`() {
        val listing = HomeShelfIndex.assemble(
            shelves = Shelves(
                collections = listOf(collection("A"), collection("B")),
                lists = listOf(list("C")),
            ),
            publications = library,
            remembered = listOf(RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "D")),
            openableSources = mapOf(serverId to "Kavita at home"),
        )

        val keys = (listing.collections + listing.lists).map { it.key }
        assertEquals(keys.size, keys.toSet().size)
    }

    private fun fetched(id: Int, title: String, isList: Boolean) = ServerShelf(
        server = KavitaPage(serverId.toString(), "Kavita at home", KavitaAddress("https://k", "key")),
        id = id,
        title = title,
        isList = isList,
    )

    @Test
    fun `what a fetch found becomes the record, both kinds`() {
        val record = HomeShelfIndex.remembering(
            listOf(
                fetched(4, "Marvel", isList = false),
                fetched(5, "Image", isList = false),
                fetched(9, "Crisis, in order", isList = true),
            ),
        )

        assertEquals(3, record.size)
        val read = record
        assertEquals(
            listOf("Crisis, in order", "Image", "Marvel"),
            read.map { it.title }.sorted(),
        )
        assertEquals(
            setOf(RememberedShelfKind.COLLECTION, RememberedShelfKind.READING_LIST),
            read.map { it.kind }.toSet(),
        )
    }

    /**
     * The record is what a fetch found, not what it has ever found. A shelf deleted on the
     * server leaves, which a merge would never let it do.
     */
    @Test
    fun `a later fetch that finds one shelf writes one shelf`() {
        val first = HomeShelfIndex.remembering(
            listOf(fetched(4, "Marvel", isList = false), fetched(5, "Image", isList = false)),
        )
        val second = HomeShelfIndex.remembering(listOf(fetched(5, "Image", isList = false)))

        assertEquals(2, first.size)
        assertEquals(1, second.size)
        assertEquals("Image", second.single().title)
    }

    /**
     * A visit to the shelves screen rewrites the record. The counts the home cards cached
     * must survive that, or the next launch draws no count again.
     */
    @Test
    fun `a later fetch keeps the count a home card cached for a shelf that is still there`() {
        val first = HomeShelfIndex.remembering(
            listOf(fetched(4, "Marvel", isList = false), fetched(9, "Crisis, in order", isList = true)),
        )
        val cached = first.map {
            if (it.kind == RememberedShelfKind.READING_LIST) it.counted(12, finished = 5) else it
        }
        val second = HomeShelfIndex.remembering(
            listOf(fetched(9, "Crisis, in order", isList = true), fetched(6, "New", isList = false)),
            previous = cached,
        )

        val list = second.single { it.serverId == 9 }
        assertEquals(12, list.count)
        assertEquals(5, list.finished)
        assertNull(second.single { it.serverId == 6 }.count)
    }

    @Test
    fun `a list's card counts every entry, and the entries the server reports as finished`() {
        val shelf = RememberedShelf(RememberedShelfKind.READING_LIST, serverId, 9, "Crisis")
        val counted = shelf.counted(
            listOf(
                KavitaReadingListItem(pagesRead = 20, pagesTotal = 20),
                KavitaReadingListItem(pagesRead = 3, pagesTotal = 20),
                KavitaReadingListItem(pagesRead = 0, pagesTotal = 20),
            ),
        )

        assertEquals(3, counted.count)
        assertEquals(1, counted.finished)
        assertEquals(shelf.key, counted.key)
    }

    @Test
    fun `a collection's card counts its series and states no position`() {
        val shelf = RememberedShelf(RememberedShelfKind.COLLECTION, serverId, 4, "Marvel")
        val counted = shelf.counted(listOf(KavitaSeries(id = 7, name = "S7"), KavitaSeries(id = 3, name = "S3")))

        assertEquals(2, counted.count)
        assertNull(counted.finished)
    }
}
