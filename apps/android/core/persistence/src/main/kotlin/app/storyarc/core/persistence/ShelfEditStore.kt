package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.ShelfEditQueue
import kotlinx.serialization.json.Json

/**
 * Edits owed to a server, on disk.
 *
 * A JSON blob in preferences, for the reason [ShelvesStore] is one: the whole queue is read
 * together to decide one reconciliation, and a store that read it piecemeal would let an
 * edit outlive the baseline that justifies pushing it. Preferences rather than the Room
 * database for the same reason -- it is one small value read and written whole, and no
 * schema migration is owed for a blob that decodes what it finds.
 *
 * Durable is the entire point. `collections-and-reading-lists` promises that an edit made
 * "while the server is unreachable" is "pushed on reconnection", and the reader who made it
 * on a train has closed the app long before the server is back. An edit that lived in a view
 * model would be gone by then.
 */
class ShelfEditStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.shelfEdits"
        private const val KEY = "queue"

        fun open(context: Context): ShelfEditStore =
            ShelfEditStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    fun queue(): ShelfEditQueue {
        val stored = preferences.getString(KEY, null) ?: return ShelfEditQueue()
        return runCatching { json.decodeFromString<ShelfEditQueue>(stored) }
            .getOrDefault(ShelfEditQueue())
    }

    fun save(queue: ShelfEditQueue) {
        preferences.edit().putString(KEY, json.encodeToString(queue)).apply()
    }

    /** Reads, changes and writes in one call, so no caller has to remember the third step. */
    fun update(change: (ShelfEditQueue) -> ShelfEditQueue) {
        save(change(queue()))
    }

    fun reset() {
        preferences.edit().clear().apply()
    }
}
