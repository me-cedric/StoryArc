package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Where a source's continued read stands, kept so a relaunch resumes it instead of starting
 * it over.
 *
 * `sources`' *More from a source than the library holds*: a source that holds more than its
 * first slice keeps reading in the background, page by page, and until this store existed
 * that progress lived only in `feature.library`'s own `LibraryViewModel.partialSources`, a
 * plain in-memory map. A reader who closed the app mid-read came back to a continuation that
 * had forgotten which page it was on and started again at the top -- a server with five
 * thousand series paid for its whole continuation again every launch. iOS's
 * `SourceReadProgressStore` is the same store.
 *
 * A flat record ([StoredSourceProgress]) rather than `feature.library`'s own
 * `SourceReadProgress`, for the same reason [ScanJournal] keeps its own `StoredPublication`:
 * this module sits under every feature, and what is durable is this store's decision, not a
 * mirror of whatever shape a caller happens to hold today.
 */
class SourceReadProgressStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.source-read-progress"
        private const val KEY = "sources"

        fun open(context: Context): SourceReadProgressStore =
            SourceReadProgressStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Where this source's continued read stood when it last stopped, or null for a fresh one. */
    fun progress(sourceId: UUID): StoredSourceProgress? = stored()[sourceId.toString()]

    /** Records where a source's continued read now stands. */
    fun record(sourceId: UUID, progress: StoredSourceProgress) {
        save(stored() + (sourceId.toString() to progress))
    }

    /** Forgets a source's progress. Called when its read finishes, or the source is gone. */
    fun clear(sourceId: UUID) {
        val all = stored()
        if (sourceId.toString() !in all) return
        save(all - sourceId.toString())
    }

    /** Forgets every source's progress. Used by a reset, and by the tests. */
    fun reset() {
        preferences.edit().clear().apply()
    }

    private fun stored(): Map<String, StoredSourceProgress> {
        val text = preferences.getString(KEY, null) ?: return emptyMap()
        return runCatching {
            json.decodeFromString<Map<String, StoredSourceProgress>>(text)
        }.getOrDefault(emptyMap())
    }

    private fun save(all: Map<String, StoredSourceProgress>) {
        preferences.edit().putString(KEY, json.encodeToString(all)).apply()
    }
}

/**
 * What is actually written for one source: how much of it a continuation has merged, how
 * much more there is when the count is known, and which page answers next.
 *
 * The same three fields `feature.library`'s own `SourceReadProgress` holds, kept separate so
 * a change to that type's shape is this store's decision to make, not an accident of a
 * `Serializable` conformance reaching it from a feature module this one sits under.
 */
@Serializable
data class StoredSourceProgress(
    val read: Int,
    val total: Int? = null,
    val nextPage: Int,
)
