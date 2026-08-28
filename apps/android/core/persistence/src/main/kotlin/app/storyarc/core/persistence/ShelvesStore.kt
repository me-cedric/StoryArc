package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin
import app.storyarc.core.model.Shelves
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Collections and reading lists, on disk.
 *
 * A JSON blob in preferences, for the reason [SourceStore] is one: the whole set is read
 * together to draw one screen, and a store that read it piecemeal would let two halves of it
 * disagree.
 *
 * Only local groupings are written. A server's collections belong to the server and are
 * fetched, not remembered -- `collections-and-reading-lists` makes the server's version win
 * on conflict, and a cached copy that outlived a server edit is exactly the stale claim that
 * rule exists to prevent.
 */
class ShelvesStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.shelves"
        private const val KEY = "shelves"

        fun open(context: Context): ShelvesStore =
            ShelvesStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    fun shelves(): Shelves {
        val stored = preferences.getString(KEY, null) ?: return Shelves()
        return runCatching { json.decodeFromString<StoredShelves>(stored).shelves() }
            .getOrDefault(Shelves())
    }

    fun save(shelves: Shelves) {
        preferences.edit().putString(KEY, json.encodeToString(StoredShelves(shelves))).apply()
    }

    fun reset() {
        preferences.edit().clear().apply()
    }
}

/** What is actually written. */
@Serializable
private data class StoredShelves(
    val collections: List<StoredCollection>,
    val lists: List<StoredList>,
) {
    constructor(shelves: Shelves) : this(
        collections = shelves.collections
            .filter { it.origin == ShelfOrigin.Local }
            .map(::StoredCollection),
        lists = shelves.lists.filter { it.origin == ShelfOrigin.Local }.map(::StoredList),
    )

    fun shelves(): Shelves = Shelves(
        collections = collections.map { it.collection() },
        lists = lists.map { it.list() },
    )
}

@Serializable
private data class StoredCollection(
    val id: String,
    val name: String,
    val members: List<String>,
    val coverMemberId: String?,
) {
    constructor(collection: PublicationCollection) : this(
        id = collection.id.toString(),
        name = collection.name,
        // Written as a sorted list so the file is stable between launches, which makes a
        // diff of it readable when something goes wrong.
        members = collection.members.sorted(),
        coverMemberId = collection.coverMemberId,
    )

    fun collection(): PublicationCollection = PublicationCollection(
        id = UUID.fromString(id),
        name = name,
        members = members.toSet(),
        coverMemberId = coverMemberId,
        origin = ShelfOrigin.Local,
    )
}

@Serializable
private data class StoredList(
    val id: String,
    val name: String,
    val entries: List<String>,
) {
    constructor(list: ReadingList) : this(
        id = list.id.toString(),
        name = list.name,
        entries = list.entries,
    )

    fun list(): ReadingList = ReadingList(
        id = UUID.fromString(id),
        name = name,
        entries = entries,
        origin = ShelfOrigin.Local,
    )
}
