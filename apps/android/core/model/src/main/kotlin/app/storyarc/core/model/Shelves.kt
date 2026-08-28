package app.storyarc.core.model

import java.util.UUID

/**
 * Where a grouping came from.
 *
 * `collections-and-reading-lists` requires local and server groupings to appear "in one
 * list, each labelled with its source" rather than segregated. A label needs something to
 * label, and this is it.
 */
sealed interface ShelfOrigin {
    data object Local : ShelfOrigin
    data class Server(val id: UUID) : ShelfOrigin

    /** The source it belongs to, if any. Null for one the reader made. */
    val sourceId: UUID? get() = (this as? Server)?.id
}

/**
 * An unordered grouping of publications -- "Image Comics", "To read with my kid".
 *
 * Deliberately not the same type as [ReadingList]. `collections-and-reading-lists` opens by
 * saying most apps conflate the two and that StoryArc will not, "because ordering is the
 * entire point of one of them". A single type with an `isOrdered` flag is that conflation
 * with an extra field.
 */
data class PublicationCollection(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    /**
     * Publication identities. A set, because a collection has no order and a publication is
     * either in it or not.
     */
    val members: Set<String> = emptySet(),
    /**
     * The cover the reader chose, when they chose one.
     *
     * Null means the composite: the spec says a collection's cover "is a composite of its
     * first four member covers unless the user sets a specific one".
     */
    val coverMemberId: String? = null,
    val origin: ShelfOrigin = ShelfOrigin.Local,
)

/**
 * An ordered sequence where the order carries meaning -- a crossover read in publication
 * order, a recommended path through a series.
 */
data class ReadingList(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    /**
     * Publication identities, in the order they are meant to be read. A list, and that is
     * the whole difference from a collection.
     */
    val entries: List<String> = emptyList(),
    val origin: ShelfOrigin = ShelfOrigin.Local,
) {
    /**
     * What comes after a publication in this list.
     *
     * `collections-and-reading-lists`: when a reader finishes an entry "the next entry in
     * list order is offered, regardless of series or source". List order, not series order
     * -- that is what a reading list is for.
     */
    fun next(after: String): String? {
        val position = entries.indexOf(after)
        if (position < 0 || position + 1 >= entries.size) return null
        return entries[position + 1]
    }

    /**
     * How far through the list a reader is.
     *
     * Counted as "everything before the first unfinished entry", not "how many are
     * finished". A reader who skipped ahead and read entry five has not read one to four,
     * and a list that said five of ten would be telling them they had.
     */
    fun position(finished: (String) -> Boolean): Int =
        entries.indexOfFirst { !finished(it) }.let { if (it < 0) entries.size else it }
}

/**
 * Every collection and reading list the reader has, and every change that can be made.
 *
 * One value type for both, because they are stored together, listed together and edited by
 * the same screens. They stay separate *types* inside it for the reason the spec gives.
 */
data class Shelves(
    val collections: List<PublicationCollection> = emptyList(),
    val lists: List<ReadingList> = emptyList(),
) {

    // Collections

    fun adding(collection: PublicationCollection): Shelves =
        if (collections.any { it.id == collection.id }) {
            this
        } else {
            copy(collections = collections + collection)
        }

    /**
     * A blank name is refused rather than stored, for the reason [SourceRegistry] refuses
     * one: every screen that names it would read as if a word were missing.
     */
    fun renamingCollection(id: UUID, name: String): Shelves {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return this
        return copy(
            collections = collections.map { if (it.id == id) it.copy(name = trimmed) else it },
        )
    }

    /**
     * Adds publications to a collection.
     *
     * Takes a set, because the spec asks for selection "in bulk from the library".
     */
    fun adding(members: Set<String>, to: UUID): Shelves = copy(
        collections = collections.map {
            if (it.id == to) it.copy(members = it.members + members) else it
        },
    )

    fun removing(members: Set<String>, from: UUID): Shelves = copy(
        collections = collections.map { collection ->
            if (collection.id != from) return@map collection
            val kept = collection.members - members
            collection.copy(
                members = kept,
                // A cover that is no longer a member is no cover. Left alone it would show
                // a book the collection does not contain.
                coverMemberId = collection.coverMemberId?.takeIf { it in kept },
            )
        },
    )

    fun settingCover(member: String?, on: UUID): Shelves = copy(
        collections = collections.map { collection ->
            if (collection.id != on) return@map collection
            if (member != null && member !in collection.members) return@map collection
            collection.copy(coverMemberId = member)
        },
    )

    fun deletingCollection(id: UUID): Shelves = copy(collections = collections.filter { it.id != id })

    // Reading lists

    fun adding(list: ReadingList): Shelves =
        if (lists.any { it.id == list.id }) this else copy(lists = lists + list)

    fun renamingList(id: UUID, name: String): Shelves {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return this
        return copy(lists = lists.map { if (it.id == id) it.copy(name = trimmed) else it })
    }

    /**
     * Appends entries, keeping the order they arrive in and skipping ones already there.
     *
     * Ordered, so this takes a list rather than a set: adding three issues of a crossover in
     * the order the reader picked them is the point.
     */
    fun appending(entries: List<String>, to: UUID): Shelves = copy(
        lists = lists.map { list ->
            if (list.id != to) return@map list
            val known = list.entries.toSet()
            list.copy(entries = list.entries + entries.filterNot { it in known })
        },
    )

    fun removing(entry: String, fromList: UUID): Shelves = copy(
        lists = lists.map {
            if (it.id == fromList) it.copy(entries = it.entries - entry) else it
        },
    )

    /**
     * Moves an entry, taking the destination a drag reports.
     *
     * The same convention [SourceRegistry.moving] uses, and for the same reason: removing
     * first and inserting after lands one place early on every downward drag.
     */
    fun moving(entry: String, destination: Int, inList: UUID): Shelves = copy(
        lists = lists.map { list ->
            if (list.id != inList) return@map list
            val from = list.entries.indexOf(entry)
            if (from < 0) return@map list
            val moved = list.entries.toMutableList()
            moved.removeAt(from)
            val to = (if (destination > from) destination - 1 else destination)
                .coerceIn(0, moved.size)
            moved.add(to, entry)
            list.copy(entries = moved)
        },
    )

    fun deletingList(id: UUID): Shelves = copy(lists = lists.filter { it.id != id })

    // Both

    /**
     * Every collection a publication belongs to.
     *
     * `collections-and-reading-lists`: "a publication may belong to any number of
     * collections". This is how a detail screen asks which.
     */
    fun collectionsContaining(member: String): List<PublicationCollection> =
        collections.filter { member in it.members }

    /**
     * Forgets everything a source defined, for when the source itself is removed.
     *
     * Local groupings are untouched: a reader's own collection is theirs, even if every
     * publication in it came from a server they just removed.
     */
    fun removingAll(sourceId: UUID): Shelves = copy(
        collections = collections.filterNot { it.origin == ShelfOrigin.Server(sourceId) },
        lists = lists.filterNot { it.origin == ShelfOrigin.Server(sourceId) },
    )
}
