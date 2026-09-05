package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.Shelves
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The home surface's assembly rules, one test per scenario in `home-screen`.
 *
 * Every one of them runs on a plain JVM with no device, no store and no source, which is
 * the point: the requirement being asserted is that the surface is a function of local
 * history alone, and a test that needed a network to prove it would be proving the
 * opposite.
 */
class HomeShelvesTest {

    private val now = 1_700_000_000_000L
    private val day = 24L * 60L * 60L * 1000L

    // Keep reading

    @Test
    fun `keep reading is ordered by when each was last read`() {
        val old = publication("old")
        val recent = publication("recent")
        val surface = assemble(
            listOf(old, recent),
            progress = mapOf(
                old.id to partRead(at = now - 5 * day),
                recent.id to partRead(at = now - day),
            ),
        )

        assertEquals(listOf("recent", "old"), surface.keepReading.map { it.publication.displayTitle })
    }

    @Test
    fun `nothing part-way through leaves keep reading absent rather than empty`() {
        val surface = assemble(listOf(publication("untouched")))

        assertTrue(surface.keepReading.isEmpty())
    }

    @Test
    fun `finishing one takes it out of keep reading without taking it out of the library`() {
        val book = publication("done")
        val surface = assemble(listOf(book), progress = mapOf(book.id to finished(at = now - day)))

        assertTrue(surface.keepReading.isEmpty())
        assertEquals(listOf("done"), surface.recentlyAdded.map { it.publication.displayTitle })
    }

    @Test
    fun `a publication that cannot be opened stays in keep reading and says so`() {
        val away = publication("away")
        val surface = assemble(
            listOf(away),
            progress = mapOf(away.id to partRead(at = now)),
            readable = { false },
        )

        assertEquals(1, surface.keepReading.size)
        assertFalse(surface.keepReading.single().isReadableNow)
    }

    @Test
    fun `one thing in progress leads with a single card rather than a carousel of one`() {
        val one = publication("only")
        val single = assemble(listOf(one), progress = mapOf(one.id to partRead(at = now)))
        assertTrue(single.leadsWithOneCard)

        val two = publication("second")
        val pair = assemble(
            listOf(one, two),
            progress = mapOf(one.id to partRead(at = now), two.id to partRead(at = now - day)),
        )
        assertFalse(pair.leadsWithOneCard)
    }

    // Up next

    @Test
    fun `the next unread issue of a started series is offered`() {
        val first = issue("Bone", "1")
        val second = issue("Bone", "2")
        val surface = assemble(
            listOf(first, second),
            progress = mapOf(first.id to finished(at = now - day)),
        )

        assertEquals(listOf("Bone 2"), surface.upNext.map { it.publication.displayTitle })
        assertTrue(surface.keepReading.isEmpty())
    }

    @Test
    fun `a part-read issue keeps its successor out of up next`() {
        val first = issue("Bone", "1")
        val second = issue("Bone", "2")
        val surface = assemble(
            listOf(first, second),
            progress = mapOf(first.id to partRead(at = now)),
        )

        assertEquals(listOf("Bone 1"), surface.keepReading.map { it.publication.displayTitle })
        assertTrue(surface.upNext.isEmpty())
    }

    @Test
    fun `the two shelves never offer the same publication`() {
        val first = issue("Bone", "1")
        val second = issue("Bone", "2")
        val third = issue("Bone", "3")
        val surface = assemble(
            listOf(first, second, third),
            progress = mapOf(first.id to finished(at = now - day), second.id to partRead(at = now)),
        )

        val shared = surface.keepReading.map { it.id }.intersect(surface.upNext.map { it.id }.toSet())
        assertTrue(shared.isEmpty())
    }

    @Test
    fun `a series read to the end contributes nothing silently`() {
        val only = issue("Bone", "1")
        val surface = assemble(listOf(only), progress = mapOf(only.id to finished(at = now - day)))

        assertTrue(surface.upNext.isEmpty())
    }

    @Test
    fun `an issue the reader skipped is not pushed back at them`() {
        val first = issue("Bone", "1")
        val second = issue("Bone", "2")
        val third = issue("Bone", "3")
        val surface = assemble(
            listOf(first, second, third),
            progress = mapOf(first.id to finished(at = now - day), third.id to finished(at = now)),
        )

        assertTrue(surface.upNext.isEmpty())
    }

    @Test
    fun `a series with nothing read at all is not started`() {
        val surface = assemble(listOf(issue("Bone", "1"), issue("Bone", "2")))

        assertTrue(surface.upNext.isEmpty())
    }

    @Test
    fun `the next issue is offered even when its source is away`() {
        val first = issue("Bone", "1")
        val second = issue("Bone", "2")
        val surface = assemble(
            listOf(first, second),
            progress = mapOf(first.id to finished(at = now - day)),
            readable = { it.number != "2" },
        )

        assertEquals(1, surface.upNext.size)
        assertFalse(surface.upNext.single().isReadableNow)
    }

    // Recently added, finished, and the shape of the surface

    @Test
    fun `recently added is newest first`() {
        val older = publication("older", addedAt = now - 10 * day)
        val newer = publication("newer", addedAt = now - day)
        val surface = assemble(listOf(older, newer))

        assertEquals(listOf("newer", "older"), surface.recentlyAdded.map { it.publication.displayTitle })
    }

    @Test
    fun `a publication with no arrival date is still offered`() {
        val undated = publication("undated", addedAt = null)
        val surface = assemble(listOf(undated))

        assertEquals(listOf("undated"), surface.recentlyAdded.map { it.publication.displayTitle })
    }

    @Test
    fun `finished publications are grouped by how long ago they were finished`() {
        val week = publication("this week")
        val month = publication("this month")
        val ancient = publication("earlier")
        val surface = assemble(
            listOf(week, month, ancient),
            progress = mapOf(
                week.id to finished(at = now - 2 * day),
                month.id to finished(at = now - 12 * day),
                ancient.id to finished(at = now - 400 * day),
            ),
        )

        assertEquals(
            listOf(HomeFinishedPeriod.THIS_WEEK, HomeFinishedPeriod.THIS_MONTH, HomeFinishedPeriod.EARLIER),
            surface.finished.map { it.period },
        )
        assertEquals(listOf("this week"), surface.finished.first().entries.map { it.publication.displayTitle })
    }

    @Test
    fun `nothing finished leaves the section absent`() {
        val surface = assemble(listOf(publication("untouched")))

        assertTrue(surface.finished.isEmpty())
    }

    @Test
    fun `a finished record with no completion date falls back to when it was last written`() {
        val book = publication("legacy")
        val record = ReadingProgress(
            identity = book.identity,
            position = ReadingPosition.Page(index = 30, total = 31),
            isFinished = true,
            finishedAtEpochMillis = null,
            updatedAtEpochMillis = now - 2 * day,
        )
        val surface = assemble(listOf(book), progress = mapOf(book.id to record))

        assertEquals(HomeFinishedPeriod.THIS_WEEK, surface.finished.single().period)
    }

    @Test
    fun `an empty library makes the surface the first-run screen`() {
        assertTrue(assemble(emptyList()).isBare)
    }

    @Test
    fun `a library with no history leads with recently added rather than a stack of headings`() {
        val surface = assemble(listOf(publication("unread")))

        assertFalse(surface.isBare)
        assertTrue(surface.keepReading.isEmpty())
        assertTrue(surface.upNext.isEmpty())
        assertEquals(1, surface.recentlyAdded.size)
    }

    // How much is left

    @Test
    fun `a paged publication says how many pages are left`() {
        val book = publication("paged")
        val record = ReadingProgress(
            identity = book.identity,
            position = ReadingPosition.Page(index = 10, total = 31),
            updatedAtEpochMillis = now,
        )

        assertEquals(20, HomeShelves.pagesRemaining(book, record))
    }

    @Test
    fun `a reflowable publication answers in pages only when it declares a page count`() {
        val counted = publication("counted").copy(pageCount = 200)
        val uncounted = publication("uncounted")
        val position = ReadingPosition.Reflowable(progression = 0.25, locator = "epubcfi(/6/4)")
        val record = { book: Publication ->
            ReadingProgress(identity = book.identity, position = position, updatedAtEpochMillis = now)
        }

        assertEquals(150, HomeShelves.pagesRemaining(counted, record(counted)))
        assertNull(HomeShelves.pagesRemaining(uncounted, record(uncounted)))
    }

    @Test
    fun `a publication that was never opened has nothing left to say`() {
        assertNull(HomeShelves.pagesRemaining(publication("fresh"), null))
    }

    // A page or less left
    //
    // `home-screen`, *A publication with nothing meaningful left*: the card then "offers to
    // finish it -- marking it read -- and offers the next in its series where there is one,
    // rather than offering to reopen its last page". Every case below is one `pagesRemaining`
    // answers null or zero to, which is exactly why the predicate is separate: several
    // different situations share those spellings and only one is *all but the last page*.

    @Test
    fun `the last page of a comic is a page or less left`() {
        val book = publication("paged")
        val at = { index: Int ->
            ReadingProgress(
                identity = book.identity,
                position = ReadingPosition.Page(index = index, total = 31),
                updatedAtEpochMillis = now,
            )
        }

        assertTrue(HomeShelves.isAtTheEnd(book, at(30)))
        assertFalse(HomeShelves.isAtTheEnd(book, at(29)))
    }

    @Test
    fun `a book nobody has opened is not at its end, though it says nothing either`() {
        // The failure this guards: `pagesRemaining` is null here too, so a card deriving the
        // offer from that would offer to *finish* a book nobody has opened.
        val fresh = publication("fresh")

        assertNull(HomeShelves.pagesRemaining(fresh, null))
        assertFalse(HomeShelves.isAtTheEnd(fresh, null))
    }

    @Test
    fun `a finished book is not at its end either, because it is past it`() {
        val book = publication("done")
        val record = ReadingProgress(
            identity = book.identity,
            position = ReadingPosition.Page(index = 30, total = 31),
            isFinished = true,
            updatedAtEpochMillis = now,
        )

        assertFalse(HomeShelves.isAtTheEnd(book, record))
    }

    @Test
    fun `a reflowable book rounds to its end only against a spine count`() {
        val counted = publication("counted").copy(pageCount = 200)
        val uncounted = publication("uncounted")
        val nearlyDone = ReadingPosition.Reflowable(progression = 0.999, locator = "epubcfi(/6/4)")
        val record = { book: Publication ->
            ReadingProgress(identity = book.identity, position = nearlyDone, updatedAtEpochMillis = now)
        }

        assertTrue(HomeShelves.isAtTheEnd(counted, record(counted)))
        // "A page or less" needs a page to be a thing, and here the app has only a fraction.
        assertFalse(HomeShelves.isAtTheEnd(uncounted, record(uncounted)))
    }

    // Pinned shelves

    @Test
    fun `a pinned collection becomes a shelf of its own, between recently added and finished`() {
        val one = publication("Ashfall")
        val two = publication("Brine")
        val collection = PublicationCollection(name = "For bedtime", members = setOf(one.id))
        val shelves = Shelves(collections = listOf(collection))
        val pinned = PinnedShelves().toggling(ShelfPin.Collection(collection.id))

        val surface = assemble(listOf(one, two), shelves = shelves, pins = pinned)

        assertEquals(1, surface.pinned.size)
        assertEquals("For bedtime", surface.pinned.single().name)
        assertEquals(listOf(one.id), surface.pinned.single().entries.map { it.id })
    }

    @Test
    fun `an unpinned shelf contributes nothing, which is what unpinning has to mean`() {
        val one = publication("Ashfall")
        val collection = PublicationCollection(name = "For bedtime", members = setOf(one.id))
        val shelves = Shelves(collections = listOf(collection))

        // The same shelves, no pins. `home-screen`: unpinning "removes the shelf without
        // altering the collection or the list" -- so the collection is untouched either way,
        // which is the assertion below the obvious one.
        val surface = assemble(listOf(one), shelves = shelves, pins = PinnedShelves())

        assertTrue(surface.pinned.isEmpty())
        assertEquals(setOf(one.id), shelves.collections.single().members)
    }

    @Test
    fun `a reading list keeps its own order, which a collection has none of`() {
        // The whole difference between the two types, made concrete on this surface: a list's
        // entries decide the order, and a collection is filtered out of the library in the
        // library's order.
        val first = publication("Ashfall")
        val second = publication("Brine")
        val list = ReadingList(name = "Crossover", entries = listOf(second.id, first.id))
        val shelves = Shelves(lists = listOf(list))
        val pinned = PinnedShelves().toggling(ShelfPin.ReadingListPin(list.id))

        val surface = assemble(listOf(first, second), shelves = shelves, pins = pinned)

        assertEquals(listOf(second.id, first.id), surface.pinned.single().entries.map { it.id })
    }

    @Test
    fun `a pinned shelf the library cannot fill is absent rather than an empty heading`() {
        // Not only a collection the reader emptied: a shelf whose members live on a source no
        // scan has reached resolves to nothing too, and a heading over no covers would be the
        // surface looking like it was waiting for something.
        val absent = PublicationCollection(name = "On the server", members = setOf("nothing-here"))
        val shelves = Shelves(collections = listOf(absent))
        val pinned = PinnedShelves().toggling(ShelfPin.Collection(absent.id))

        assertTrue(assemble(listOf(publication("Ashfall")), shelves = shelves, pins = pinned).pinned.isEmpty())
    }

    @Test
    fun `a list entry the library does not hold is skipped rather than left as a hole`() {
        val held = publication("Ashfall")
        val list = ReadingList(name = "Crossover", entries = listOf("missing", held.id, "also-missing"))
        val shelves = Shelves(lists = listOf(list))
        val pinned = PinnedShelves().toggling(ShelfPin.ReadingListPin(list.id))

        val surface = assemble(listOf(held), shelves = shelves, pins = pinned)

        assertEquals(listOf(held.id), surface.pinned.single().entries.map { it.id })
    }

    // Fixtures

    private fun assemble(
        publications: List<Publication>,
        progress: Map<String, ReadingProgress> = emptyMap(),
        readable: (Publication) -> Boolean = { true },
        shelves: Shelves = Shelves(),
        pins: PinnedShelves = PinnedShelves(),
    ) = HomeShelves.assemble(
        publications = publications,
        progress = { progress[it.id] },
        isReadableNow = readable,
        nowEpochMillis = now,
        shelves = shelves,
        pinned = pins,
    )

    private fun publication(
        title: String,
        addedAt: Long? = now,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.EMBEDDED,
        addedAtEpochMillis = addedAt,
    )

    private fun issue(series: String, number: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$series-$number.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "$series $number",
        series = series,
        number = number,
        origin = MetadataOrigin.EMBEDDED,
        addedAtEpochMillis = now,
    )

    private fun partRead(at: Long) = ReadingProgress(
        identity = PublicationIdentity(),
        position = ReadingPosition.Page(index = 4, total = 31),
        updatedAtEpochMillis = at,
    )

    private fun finished(at: Long) = ReadingProgress(
        identity = PublicationIdentity(),
        position = ReadingPosition.Page(index = 30, total = 31),
        isFinished = true,
        finishedAtEpochMillis = at,
        updatedAtEpochMillis = at,
    )
}
