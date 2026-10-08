package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList
import app.storyarc.core.model.ShelfOrigin
import app.storyarc.core.model.ShelfStamps
import app.storyarc.core.model.ShelfTombstone
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
class ShelvesStore internal constructor(
    private val preferences: SharedPreferences,
    private val now: () -> Long = System::currentTimeMillis,
) {

    companion object {
        private const val NAME = "app.storyarc.shelves"
        private const val KEY = "shelves"

        fun open(context: Context): ShelvesStore =
            ShelvesStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    fun shelves(): Shelves = stored()?.shelves() ?: Shelves()

    /** The shelves the reader deleted, kept so a sync carries the deletion. */
    fun removed(): List<ShelfTombstone> = stored()?.removed().orEmpty()

    /**
     * Writes what a screen changed: each change is stamped and each deletion recorded.
     * `library-sync` tasks 3.3 and 3.4; see [ShelfStamps.stamped].
     */
    fun save(shelves: Shelves) = save(shelves, removed())

    /** Writes shelves and deletions together, as an import leaves them. */
    fun save(shelves: Shelves, removed: List<ShelfTombstone>) {
        val stamped = ShelfStamps.stamped(this.shelves(), removed(), shelves, removed, now())
        restore(stamped.shelves, stamped.removed)
    }

    /** Writes shelves and deletions exactly as given: a sync, or the undo of a failed write. */
    fun restore(shelves: Shelves, removed: List<ShelfTombstone>) {
        preferences.edit().putString(KEY, json.encodeToString(StoredShelves(shelves, removed))).apply()
    }

    private fun stored(): StoredShelves? = preferences.getString(KEY, null)?.let {
        runCatching { json.decodeFromString<StoredShelves>(it) }.getOrNull()
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
    // Absent before `library-sync`; read as no deletion.
    val removed: List<StoredShelfTombstone> = emptyList(),
) {
    constructor(shelves: Shelves, removed: List<ShelfTombstone>) : this(
        collections = shelves.collections
            .filter { it.origin == ShelfOrigin.Local }
            .map(::StoredCollection),
        lists = shelves.lists.filter { it.origin == ShelfOrigin.Local }.map(::StoredList),
        removed = removed.map { StoredShelfTombstone(it.id.toString(), it.removedAtEpochMillis) },
    )

    fun shelves(): Shelves = Shelves(
        collections = collections.map { it.collection() },
        lists = lists.map { it.list() },
    )

    fun removed(): List<ShelfTombstone> = removed.mapNotNull { stored ->
        runCatching { ShelfTombstone(UUID.fromString(stored.id), stored.removedAt) }.getOrNull()
    }
}

@Serializable
private data class StoredShelfTombstone(val id: String, val removedAt: Long)

@Serializable
private data class StoredCollection(
    val id: String,
    val name: String,
    val members: List<String>,
    val coverMemberId: String?,
    // Absent before `library-sync`; the epoch, which any deletion outranks.
    val changedAt: Long = 0,
) {
    constructor(collection: PublicationCollection) : this(
        id = collection.id.toString(),
        name = collection.name,
        // Written as a sorted list so the file is stable between launches, which makes a
        // diff of it readable when something goes wrong.
        members = collection.members.sorted(),
        coverMemberId = collection.coverMemberId,
        changedAt = collection.changedAtEpochMillis,
    )

    fun collection(): PublicationCollection = PublicationCollection(
        id = UUID.fromString(id),
        name = name,
        members = members.toSet(),
        coverMemberId = coverMemberId,
        origin = ShelfOrigin.Local,
        changedAtEpochMillis = changedAt,
    )
}

@Serializable
private data class StoredList(
    val id: String,
    val name: String,
    val entries: List<String>,
    // Absent on a record written before task 7.13; `ignoreUnknownKeys` and the default
    // below read that the same way as an explicit null, so no migration is needed.
    val coverMemberId: String? = null,
    val changedAt: Long = 0,
) {
    constructor(list: ReadingList) : this(
        id = list.id.toString(),
        name = list.name,
        entries = list.entries,
        coverMemberId = list.coverMemberId,
        changedAt = list.changedAtEpochMillis,
    )

    fun list(): ReadingList = ReadingList(
        id = UUID.fromString(id),
        name = name,
        entries = entries,
        coverMemberId = coverMemberId,
        origin = ShelfOrigin.Local,
        changedAtEpochMillis = changedAt,
    )
}
