package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.json.Json

/**
 * What the reader chose on the end screen about a finished download (D7).
 *
 * Two sets of download ids. **Kept**: the automatic sweep skips these from now on.
 * **Removed on close**: the reader asked for this download to go, and it goes the next
 * time the library appears, through the same undoable removal the sweep uses. Done then
 * rather than at the tap, because the undo is shown in the library: removed at the tap,
 * its ten seconds ran out behind the reader that was still open.
 *
 * Its own small store rather than a field on [app.storyarc.core.model.Download]: the
 * sweep already asks [DownloadStore] which download is finished, and these questions
 * need only an id. iOS's `CleanupChoices` is the same shape.
 */
class CleanupChoices(private val preferences: SharedPreferences) {
    companion object {
        private const val NAME = "app.storyarc.downloads.keptFromCleanup"
        private const val KEPT = "ids"
        private const val REMOVE_ON_CLOSE = "removeOnClose"

        fun open(context: Context): CleanupChoices =
            CleanupChoices(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Whether the sweep skips [id]'s download. */
    fun isKept(id: String): Boolean = ids(KEPT).contains(id)

    /** Exempts [id]'s download from the sweep from now on, and withdraws a removal the
     * reader asked for. */
    fun keep(id: String) {
        save(KEPT, ids(KEPT) + id)
        save(REMOVE_ON_CLOSE, ids(REMOVE_ON_CLOSE) - id)
    }

    /** Asks for [id]'s download to go when the reader closes, sweep or no sweep. */
    fun removeOnClose(id: String) {
        save(REMOVE_ON_CLOSE, ids(REMOVE_ON_CLOSE) + id)
    }

    /** Whether [id]'s download goes when the reader closes: the reader asked for it, or
     * the sweep is on and the reader has not kept it. */
    fun isRemovedOnClose(id: String, automaticCleanupIsOn: Boolean): Boolean =
        ids(REMOVE_ON_CLOSE).contains(id) || (automaticCleanupIsOn && !isKept(id))

    /** The removals the reader asked for, which this then forgets. */
    fun takeRemovals(): Set<String> {
        val removals = ids(REMOVE_ON_CLOSE)
        save(REMOVE_ON_CLOSE, emptySet())
        return removals
    }

    private fun ids(key: String): Set<String> =
        preferences.getString(key, null)
            ?.let { runCatching { json.decodeFromString<Set<String>>(it) }.getOrNull() }
            ?: emptySet()

    private fun save(key: String, ids: Set<String>) {
        preferences.edit().putString(key, json.encodeToString(ids)).apply()
    }
}
