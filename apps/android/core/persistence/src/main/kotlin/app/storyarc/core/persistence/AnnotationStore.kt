package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.inReadingOrder
import kotlinx.serialization.json.Json

/**
 * Highlights and notes, on disk, keyed by the publication they are in.
 *
 * A JSON blob in preferences, for the reason [BookmarkStore] is one: one publication's marks
 * are read together to draw one list, and a store that read them piecemeal would let two
 * halves of that list disagree.
 *
 * Not in the cache directory. What a reader wrote is the least replaceable thing this app
 * holds -- a lost highlight is not a rescan, it is a passage they will not find again.
 *
 * iOS's `AnnotationStore` writes the same shape.
 */
class AnnotationStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.annotations"
        private const val KEY = "annotations"

        fun open(context: Context): AnnotationStore =
            AnnotationStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Every mark in one publication, in book order. */
    fun annotations(publication: String): List<Annotation> =
        stored()[publication].orEmpty().inReadingOrder()

    /**
     * Adds a mark, or replaces the one with the same identity.
     *
     * One method rather than an add beside an update, because editing a note is the same act
     * as making one: the reader has something to say about those words.
     */
    fun save(annotation: Annotation, publication: String): List<Annotation> {
        val all = stored().toMutableMap()
        val marks = all[publication].orEmpty()
        val updated =
            if (marks.any { it.id == annotation.id }) {
                marks.map { if (it.id == annotation.id) annotation else it }
            } else {
                marks + annotation
            }
        write(all, publication, updated)
        return updated.inReadingOrder()
    }

    fun remove(id: String, publication: String): List<Annotation> {
        val all = stored().toMutableMap()
        val updated = all[publication].orEmpty().filterNot { it.id == id }
        write(all, publication, updated)
        return updated.inReadingOrder()
    }

    /** Forgets one publication's marks. What removing a publication takes with it. */
    fun clear(publication: String) {
        write(stored().toMutableMap(), publication, emptyList())
    }

    /** Forgets everything. The Privacy screen's reading history, and the tests. */
    fun reset() {
        preferences.edit().remove(KEY).apply()
    }

    private fun stored(): Map<String, List<Annotation>> {
        val raw = preferences.getString(KEY, null) ?: return emptyMap()
        return runCatching { json.decodeFromString<Map<String, List<Annotation>>>(raw) }
            .getOrDefault(emptyMap())
    }

    private fun write(
        all: MutableMap<String, List<Annotation>>,
        publication: String,
        marks: List<Annotation>,
    ) {
        if (marks.isEmpty()) all.remove(publication) else all[publication] = marks
        preferences.edit().putString(KEY, json.encodeToString(all.toMap())).apply()
    }
}
