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

/**
 * One thing waiting to reach a server that was not there when it happened.
 *
 * A position, or a deliberate mark. They are held together because they are the same
 * promise -- "this reaches the server when the server comes back" -- and a second queue
 * would be a second thing to forget to flush.
 */
@Serializable
data class KavitaUnsent(
    val origin: KavitaOrigin,
    val page: Int,
    /** Null for a position. True or false for a mark the reader made deliberately. */
    val mark: Boolean? = null,
    /** Set when this is an append to one of the server's reading lists. */
    val listId: Int? = null,
) {
    /**
     * What makes two held items the same thing.
     *
     * The chapter alone is not enough: a position, a mark and a list append can all be
     * waiting for the same chapter, and they are three different promises.
     */
    val key: String get() = listOf(origin.chapterId, listId, mark).joinToString(":")
}

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

    /**
     * The publication one chapter was read as, if this device has ever opened it.
     *
     * The inverse of [remember], and what a pull needs: a server reports progress against a
     * chapter id, and the local store keys on the publication the reader opened. Without
     * this the two never meet and a merge silently matches nothing, which is worse than not
     * merging at all -- it looks like synchronisation and is not.
     *
     * Null for a chapter this device has not opened. `reading-progress` still wants that
     * position, but it belongs to a publication the library does not hold yet, and inventing
     * an identity for it would be inventing a reading.
     */
    fun publicationForChapter(chapterId: Int): String? =
        origins().entries.firstOrNull { it.value.chapterId == chapterId }?.key

    /** Keeps a position that could not be sent. One per chapter: the latest page wins. */
    fun hold(unsent: KavitaUnsent) {
        val kept = unsent().filterNot { it.key == unsent.key } + unsent
        preferences.edit().putString(UNSENT, encodeUnsent(kept)).apply()
    }

    /** Everything still waiting for a server. */
    fun unsent(): List<KavitaUnsent> =
        preferences.getString(UNSENT, null)
            ?.let { runCatching { json.decodeFromString<List<KavitaUnsent>>(it) }.getOrNull() }
            ?: emptyList()

    /** Drops the positions that reached the server. */
    fun sent(delivered: List<KavitaUnsent>) {
        val keys = delivered.map { it.key }.toSet()
        val kept = unsent().filterNot { it.key in keys }
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
