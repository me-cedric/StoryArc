package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.Bookmark
import app.storyarc.core.model.inReadingOrder
import app.storyarc.core.model.markAt
import kotlinx.serialization.json.Json

/**
 * Bookmarks, on disk, keyed by the publication they are in.
 *
 * A JSON blob in preferences, for the reason [ShelvesStore] is one: one publication's marks
 * are read together to draw one list, and a store that read them piecemeal would let two
 * halves of that list disagree.
 *
 * Not in the cache directory, unlike [LibraryCache]. A bookmark is something a reader made;
 * losing it costs them work rather than costing a rescan, so it belongs with the reading
 * position and not with the things the system may reclaim.
 *
 * iOS's `BookmarkStore` writes the same shape.
 */
class BookmarkStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.bookmarks"
        private const val KEY = "bookmarks"

        fun open(context: Context): BookmarkStore =
            BookmarkStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Every mark in one publication, in book order. */
    fun bookmarks(publication: String): List<Bookmark> =
        stored()[publication].orEmpty().inReadingOrder()

    /**
     * Adds a mark, or removes the one already on that page.
     *
     * One control rather than two. A reader who presses it on a page they have already
     * marked means "no longer", and a second identical entry in the list would be the
     * button refusing to answer that.
     *
     * Returns what the publication holds afterwards, so a caller does not have to read back
     * what it just wrote.
     */
    fun toggle(bookmark: Bookmark, publication: String): List<Bookmark> {
        val all = stored().toMutableMap()
        val marks = all[publication].orEmpty()
        val existing = marks.markAt(bookmark.progression, bookmark.resource)
        val updated =
            if (existing == null) marks + bookmark else marks.filterNot { it.id == existing.id }
        write(all, publication, updated)
        return updated.inReadingOrder()
    }

    /** Removes one mark by identity, which is what the list offers. */
    fun remove(id: String, publication: String): List<Bookmark> {
        val all = stored().toMutableMap()
        val updated = all[publication].orEmpty().filterNot { it.id == id }
        write(all, publication, updated)
        return updated.inReadingOrder()
    }

    /** Forgets one publication's marks. What removing a publication takes with it. */
    fun clear(publication: String) {
        val all = stored().toMutableMap()
        write(all, publication, emptyList())
    }

    /** Forgets everything. The Privacy screen's reading history, and the tests. */
    fun reset() {
        preferences.edit().remove(KEY).apply()
    }

    private fun stored(): Map<String, List<Bookmark>> {
        val raw = preferences.getString(KEY, null) ?: return emptyMap()
        return runCatching { json.decodeFromString<Map<String, List<Bookmark>>>(raw) }
            .getOrDefault(emptyMap())
    }

    private fun write(
        all: MutableMap<String, List<Bookmark>>,
        publication: String,
        marks: List<Bookmark>,
    ) {
        if (marks.isEmpty()) all.remove(publication) else all[publication] = marks
        preferences.edit().putString(KEY, json.encodeToString(all.toMap())).apply()
    }
}
