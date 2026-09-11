package app.storyarc.feature.library

import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.Publication
import app.storyarc.core.model.RememberedShelf
import app.storyarc.core.model.RememberedShelfKind
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.Shelves
import java.util.UUID

/** Where a card on the home surface leads. */
sealed interface HomeShelfDestination {

    /** A shelf the reader made here. Its own detail screen, as from the shelves screen. */
    data class OnDevice(val id: UUID) : HomeShelfDestination

    /**
     * A shelf a server defined. The record is what opens it again, because the server's own
     * numbering is the only name it has.
     */
    data class OnServer(val shelf: RememberedShelf) : HomeShelfDestination
}

/**
 * One shelf as the home surface names it.
 *
 * Deliberately not a [app.storyarc.core.model.PublicationCollection] or a
 * [app.storyarc.core.model.ReadingList]: the home surface lists both kinds and a server's as
 * well, and the three carry different amounts of truth. What they have in common is a name,
 * some artwork and somewhere to go, which is exactly this.
 */
data class HomeShelfSummary(
    val kind: RememberedShelfKind,
    val name: String,
    /**
     * How many publications are in it, or null for a server's shelf whose size this device
     * does not know. Null draws no count rather than a zero that would be a lie.
     */
    val count: Int?,
    /** The source's name, or null for a shelf the reader made here. */
    val sourceName: String?,
    /**
     * The publications behind the composite, in the order they are drawn.
     *
     * Resolved here rather than left as identities, so the card can load artwork through the
     * home surface's own `cover` lambda and this file stays the only place that knows which
     * four a shelf stands on. A member this device does not hold is left out, which is the one
     * place the home surface's composite is narrower than the shelves screen's: that one keeps
     * the identity and blanks its quadrant. A remembered shelf has no local members at all, so
     * its list is empty and its card is the cover-shaped blank.
     */
    val tiles: List<Publication>,
    /**
     * How many of an ordered shelf's entries are behind the reader. Null for a collection,
     * which has no order and therefore no position in one -- and which is what makes the two
     * kinds tell apart on a card as well as in a heading.
     */
    val finished: Int?,
    val destination: HomeShelfDestination,
) {

    /**
     * How far through the shelf the reader is, nought to one, or null where there is no order
     * to be part-way through. Counted rather than stored, so the rail and the count under the
     * name cannot disagree.
     */
    val fraction: Float?
        get() {
            val done = finished ?: return null
            val total = count ?: return null
            return if (total <= 0) 0f else done.toFloat() / total
        }

    /** Stable across a rename and unique across the two kinds and the two origins. */
    val key: String
        get() = when (val where = destination) {
            is HomeShelfDestination.OnDevice -> "local:${where.id}"
            is HomeShelfDestination.OnServer -> where.shelf.token
        }
}

/**
 * The reader's shelves, as two shelves of the home surface.
 *
 * `collections-and-reading-lists`, *Shelves on the home surface*: two and not one, because a
 * reading list is ordered and a collection is not, and because merging them would need a name
 * for a merged idea that neither platform ships. Each half is drawn only when it holds
 * something, so a reader with collections and no lists meets one heading.
 */
data class HomeShelfListing(
    val collections: List<HomeShelfSummary> = emptyList(),
    val lists: List<HomeShelfSummary> = emptyList(),
) {
    val isEmpty: Boolean get() = collections.isEmpty() && lists.isEmpty()
}

/**
 * Assembles [HomeShelfListing] out of local curation alone.
 *
 * Pure, and asserted on a plain JVM the way [HomeShelves] is. **Nothing here reaches a
 * source.** `home-screen` requires the home surface to render "with the same shelves in the
 * same order as when the sources are up", so a server's shelf arrives as a [RememberedShelf]
 * -- a record of what that server last answered -- rather than as a request.
 *
 * iOS's `HomeShelfListing` is the same assembly.
 */
object HomeShelfIndex {

    /**
     * @param openableSources the sources the app can actually open right now, by id, with the
     *   name to label them by. A remembered shelf whose source is not here is left out: the
     *   source has been removed, or has lost the key its shelf would need, and a card that
     *   cannot lead anywhere is worse than no card. The record itself is left alone -- writing
     *   to storage while drawing turns a redraw into a write.
     * @param finished which publications are read, for a reading list's position.
     * @param pinned the reader's own order: pinned shelves lead each half, stable within both
     *   groups, by the one rule [PinnedShelves.ordering] already applies on the shelves screen.
     */
    fun assemble(
        shelves: Shelves,
        publications: List<Publication>,
        remembered: List<RememberedShelf> = emptyList(),
        openableSources: Map<UUID, String> = emptyMap(),
        finished: Set<String> = emptySet(),
        pinned: PinnedShelves = PinnedShelves(),
    ): HomeShelfListing {
        val byId = publications.associateBy { it.id }
        val tiles: (List<String>) -> List<Publication> = { ids -> ids.mapNotNull { byId[it] } }

        val collections = pinned
            .ordering(shelves.collections) { ShelfPin.Collection(it.id) }
            .map { collection ->
                HomeShelfSummary(
                    kind = RememberedShelfKind.COLLECTION,
                    name = collection.name,
                    count = collection.members.size,
                    sourceName = collection.origin.sourceId?.let { openableSources[it] },
                    tiles = tiles(shelfTiles(collection)),
                    finished = null,
                    destination = HomeShelfDestination.OnDevice(collection.id),
                )
            }

        val lists = pinned
            .ordering(shelves.lists) { ShelfPin.ReadingListPin(it.id) }
            .map { list ->
                HomeShelfSummary(
                    kind = RememberedShelfKind.READING_LIST,
                    name = list.name,
                    count = list.entries.size,
                    sourceName = list.origin.sourceId?.let { openableSources[it] },
                    tiles = tiles(shelfTiles(list)),
                    finished = list.position { it in finished },
                    destination = HomeShelfDestination.OnDevice(list.id),
                )
            }

        val server = remembered
            .filter { it.sourceId in openableSources }
            .map { shelf ->
                HomeShelfSummary(
                    kind = shelf.kind,
                    name = shelf.title,
                    count = null,
                    sourceName = openableSources[shelf.sourceId],
                    tiles = emptyList(),
                    finished = null,
                    destination = HomeShelfDestination.OnServer(shelf),
                )
            }

        return HomeShelfListing(
            collections = collections + server.filter { it.kind == RememberedShelfKind.COLLECTION },
            lists = lists + server.filter { it.kind == RememberedShelfKind.READING_LIST },
        )
    }

    /**
     * What a fetch found, as the record to write down.
     *
     * The whole record, replacing whatever was there: the fetch asks every configured server,
     * so its answer is the complete set and a merge would only keep shelves that have since
     * been deleted on a server. Pure so a test can assert that, which is the half a screen
     * cannot show.
     */
    fun remembering(fetched: List<ServerShelf>): List<RememberedShelf> =
        fetched.mapNotNull { shelf ->
            val source = runCatching { UUID.fromString(shelf.server.id) }.getOrNull()
                ?: return@mapNotNull null
            RememberedShelf(
                kind = if (shelf.isList) {
                    RememberedShelfKind.READING_LIST
                } else {
                    RememberedShelfKind.COLLECTION
                },
                sourceId = source,
                serverId = shelf.id,
                title = shelf.title,
            )
        }
}
