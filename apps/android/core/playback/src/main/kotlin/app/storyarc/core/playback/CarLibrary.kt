package app.storyarc.core.playback

import android.content.Context
import android.content.SharedPreferences

/**
 * One audiobook, as a car screen shows it.
 *
 * The URIs are here because a car that lists a book must be able to start it. `:core:playback`
 * holds no library, so nothing else in the service can turn an id into audio.
 */
data class CarBook(
    val id: String,
    val title: String,
    val durationMillis: Long? = null,
    val artworkUri: String? = null,
    val uris: List<String>,
)

/**
 * The audiobooks on the device, where `PlaybackService` can read them.
 *
 * A car asks for a list before the app has started, and the system starts the service alone for
 * that question. A preferences file answers it without a scope and without a database, which is
 * why `PlaybackMemory` has the same shape.
 *
 * The rows are a cache and go stale between writes. A stale row costs the listener one row,
 * because `onGetItem` refuses an id it cannot resolve rather than playing the wrong book.
 */
internal class CarLibrary(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): CarLibrary =
            CarLibrary(
                context.applicationContext
                    .getSharedPreferences("app.storyarc.playback.library", Context.MODE_PRIVATE),
            )

        private const val COUNT = "count"
        private const val ID = "id."
        private const val TITLE = "title."
        private const val DURATION = "duration."
        private const val ARTWORK = "artwork."
        private const val URIS = "uris."

        private const val SEPARATOR = "\n"

        private const val NO_DURATION = -1L
    }

    fun books(): List<CarBook> =
        (0 until preferences.getInt(COUNT, 0)).mapNotNull(::bookAt)

    fun publish(books: List<CarBook>) {
        preferences.edit().apply {
            clear()
            putInt(COUNT, books.size)
            books.forEachIndexed { index, book ->
                putString(ID + index, book.id)
                putString(TITLE + index, book.title)
                putLong(DURATION + index, book.durationMillis ?: NO_DURATION)
                putString(ARTWORK + index, book.artworkUri)
                putString(URIS + index, book.uris.joinToString(SEPARATOR))
            }
        }.apply()
    }

    private fun bookAt(index: Int): CarBook? {
        val id = preferences.getString(ID + index, null) ?: return null
        val uris = preferences.getString(URIS + index, null)?.split(SEPARATOR).orEmpty()
        if (uris.isEmpty() || uris.any { it.isEmpty() }) return null
        return CarBook(
            id = id,
            title = preferences.getString(TITLE + index, null).orEmpty(),
            durationMillis = preferences.getLong(DURATION + index, NO_DURATION)
                .takeIf { it != NO_DURATION },
            artworkUri = preferences.getString(ARTWORK + index, null),
            uris = uris,
        )
    }
}

/**
 * The shelf a car browses: the book in progress first, then every other audiobook, each once.
 */
internal object CarShelf {

    /**
     * Every row under the root, in the order a car draws them.
     *
     * The book in progress is first, because a car screen is read at a glance. It appears
     * once, because the published shelf holds it as well.
     */
    fun children(inProgress: PlayedBook?, shelf: List<CarBook>): List<PlayedBook> =
        listOfNotNull(inProgress) +
            shelf.filterNot { it.id == inProgress?.id }.map(CarBook::asPlayed)

    /**
     * One page of those rows.
     *
     * A head unit asks for a page at a time. A browser that ignores the number answers page
     * zero again, and the car then draws every book twice.
     *
     * The whole list where the numbers say nothing: media3 asks for the lot with a page size
     * of `Int.MAX_VALUE`, and a page of everything is what that means.
     */
    fun <T> page(rows: List<T>, page: Int, pageSize: Int): List<T> {
        if (page < 0 || pageSize <= 0) return rows
        val from = page.toLong() * pageSize
        if (from >= rows.size) return emptyList()
        return rows.subList(from.toInt(), minOf(from + pageSize, rows.size.toLong()).toInt())
    }
}

internal fun CarBook.asPlayed(): PlayedBook = PlayedBook(
    id = id,
    title = title,
    author = null,
    artworkUri = artworkUri,
    uris = uris,
    partTitles = uris.map { "" },
    partIndex = 0,
    offsetMillis = 0,
    durationMillis = durationMillis,
)
