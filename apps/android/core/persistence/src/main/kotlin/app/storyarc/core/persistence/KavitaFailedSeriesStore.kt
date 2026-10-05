package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Series whose volumes call failed while a Kavita source's continued read passed over them,
 * kept so they get another try instead of staying lost until the whole continuation runs
 * again.
 *
 * `sources`' *More from a source than the library holds* keeps a page moving past a series it
 * cannot read right now -- one unreadable series must not cost a reader the rest of the page.
 * Before this store existed, that series was gone for good: the page that skipped it never
 * asks for it again, so nothing short of the whole first-slice-and-continuation read starting
 * over would have given it a second chance, and [SourceReadProgressStore] now makes sure that
 * never happens on its own. iOS's `KavitaFailedSeriesStore` is the same store.
 */
class KavitaFailedSeriesStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.kavita-failed-series"
        private const val KEY = "sources"

        fun open(context: Context): KavitaFailedSeriesStore =
            KavitaFailedSeriesStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** The series ids of this source still waiting for a successful volumes call. */
    fun pending(sourceId: UUID): Set<Int> = stored()[sourceId.toString()].orEmpty()

    /**
     * Replaces this source's whole pending set.
     *
     * The whole set each time rather than an add or a remove: the caller already knows which
     * ids still fail after its own retry pass, and a store that merged partial writes could
     * resurrect an id a caller had just confirmed had succeeded.
     */
    fun record(sourceId: UUID, pending: Set<Int>) {
        val all = stored()
        if (pending.isEmpty()) {
            if (sourceId.toString() !in all) return
            save(all - sourceId.toString())
        } else {
            save(all + (sourceId.toString() to pending))
        }
    }

    /** Forgets a source's pending retries outright. Called when the source itself is gone. */
    fun clear(sourceId: UUID) {
        val all = stored()
        if (sourceId.toString() !in all) return
        save(all - sourceId.toString())
    }

    /** Forgets every source's pending retries. Used by a reset, and by the tests. */
    fun reset() {
        preferences.edit().clear().apply()
    }

    private fun stored(): Map<String, Set<Int>> {
        val text = preferences.getString(KEY, null) ?: return emptyMap()
        return runCatching {
            json.decodeFromString<Map<String, Set<Int>>>(text)
        }.getOrDefault(emptyMap())
    }

    private fun save(all: Map<String, Set<Int>>) {
        preferences.edit().putString(KEY, json.encodeToString(all)).apply()
    }
}
