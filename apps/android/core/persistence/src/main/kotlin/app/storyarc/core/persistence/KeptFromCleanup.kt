package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.json.Json

/**
 * Downloads exempted from the automatic sweep.
 *
 * Decision D7: with automatic cleanup on, the end screen states that this download goes
 * when the reader closes, with a "Keep" action that exempts it. Its own small store
 * rather than a field on [app.storyarc.core.model.Download] -- the sweep already asks
 * [DownloadStore] which download is finished, and asking it which is exempt needs only
 * an id, not a change to the download record or how it is stored. iOS's
 * `KeptFromCleanup` is the same shape.
 */
class KeptFromCleanup(private val preferences: SharedPreferences) {
    companion object {
        private const val NAME = "app.storyarc.downloads.keptFromCleanup"
        private const val KEY = "ids"

        fun open(context: Context): KeptFromCleanup =
            KeptFromCleanup(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Whether [id]'s download has been kept from the sweep. */
    fun contains(id: String): Boolean = ids().contains(id)

    /** Exempts [id]'s download from the sweep, from now on. */
    fun keep(id: String) {
        save(ids() + id)
    }

    private fun ids(): Set<String> =
        preferences.getString(KEY, null)
            ?.let { runCatching { json.decodeFromString<Set<String>>(it) }.getOrNull() }
            ?: emptySet()

    private fun save(ids: Set<String>) {
        preferences.edit().putString(KEY, json.encodeToString(ids)).apply()
    }
}
