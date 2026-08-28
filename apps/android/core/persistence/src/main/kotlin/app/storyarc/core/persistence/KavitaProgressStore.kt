package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Which server chapter a publication came from.
 *
 * The reader knows nothing about Kavita and should not: it opens a file. This is the note
 * the browser leaves behind so that, when the reader closes, the app can tell the server
 * where they got to.
 */
@Serializable
data class KavitaOrigin(
    val sourceId: String,
    val libraryId: Int,
    val seriesId: Int,
    val volumeId: Int,
    val chapterId: Int,
)

/** One position waiting to reach a server that was not there when it was read. */
@Serializable
data class KavitaUnsent(val origin: KavitaOrigin, val page: Int)

/**
 * The link between a local publication and its Kavita chapter, and what has not been sent.
 *
 * `kavita-server` requires a position to be "retried on the next successful connection if it
 * fails", which needs somewhere durable to keep it: a reader who finishes a chapter on a
 * train has closed the app long before the server is reachable again.
 */
class KavitaProgressStore internal constructor(
    private val preferences: SharedPreferences,
) {
    companion object {
        private const val NAME = "app.storyarc.kavita.progress"
        private const val ORIGINS = "origins"
        private const val UNSENT = "unsent"

        fun open(context: Context): KavitaProgressStore =
            KavitaProgressStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Notes where a publication came from, replacing any earlier note for the same one. */
    fun remember(publicationId: String, origin: KavitaOrigin) {
        val all = origins() + (publicationId to origin)
        preferences.edit().putString(ORIGINS, encode(all)).apply()
    }

    /** Where a publication came from, or null when it did not come from a Kavita server. */
    fun origin(publicationId: String): KavitaOrigin? = origins()[publicationId]

    /** Keeps a position that could not be sent. One per chapter: the latest page wins. */
    fun hold(unsent: KavitaUnsent) {
        val kept = unsent().filterNot { it.origin.chapterId == unsent.origin.chapterId } + unsent
        preferences.edit().putString(UNSENT, encodeUnsent(kept)).apply()
    }

    /** Everything still waiting for a server. */
    fun unsent(): List<KavitaUnsent> =
        preferences.getString(UNSENT, null)
            ?.let { runCatching { json.decodeFromString<List<KavitaUnsent>>(it) }.getOrNull() }
            ?: emptyList()

    /** Drops the positions that reached the server. */
    fun sent(delivered: List<KavitaUnsent>) {
        val chapters = delivered.map { it.origin.chapterId }.toSet()
        val kept = unsent().filterNot { it.origin.chapterId in chapters }
        preferences.edit().putString(UNSENT, encodeUnsent(kept)).apply()
    }

    private fun origins(): Map<String, KavitaOrigin> =
        preferences.getString(ORIGINS, null)
            ?.let {
                runCatching { json.decodeFromString<Map<String, KavitaOrigin>>(it) }.getOrNull()
            }
            ?: emptyMap()

    private fun encode(value: Map<String, KavitaOrigin>): String = json.encodeToString(value)

    private fun encodeUnsent(value: List<KavitaUnsent>): String = json.encodeToString(value)
}
