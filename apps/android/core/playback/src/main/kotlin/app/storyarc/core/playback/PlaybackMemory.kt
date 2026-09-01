package app.storyarc.core.playback

import android.content.Context
import android.content.SharedPreferences

/**
 * What the app was playing, written where a service that starts on its own can read it.
 *
 * **Why this exists at all.** `MediaSession.Callback.onPlaybackResumption` is the callback
 * that makes the notification-shade carousel work: the system starts the service *without*
 * the app, asks what the listener was in the middle of, and shows nothing at all if the
 * answer is nothing. `PlaybackService` answered from a process-wide field, which is null in
 * exactly the case the callback exists for — a process that has just been created. So the
 * callback was written and could never fire usefully, and the same emptiness left
 * `onGetChildren` with nothing to hand a car.
 *
 * **A preferences file rather than the library's database.** `:core:playback` decodes audio
 * and has no business knowing that a library keeps one, and a service the system has just
 * started has no scope to read one with. What is kept here is not a reading position — that
 * is `reading-progress`'s, stored by the app — but the handful of strings needed to put the
 * audio back where it was: the URIs, the titles and an offset. The two agreeing is the app's
 * job, and the app writes both.
 *
 * Read synchronously, which is the point: `onPlaybackResumption` has to answer a system that
 * is already showing a row.
 */
internal class PlaybackMemory(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): PlaybackMemory =
            PlaybackMemory(
                context.applicationContext
                    .getSharedPreferences("app.storyarc.playback.memory", Context.MODE_PRIVATE),
            )

        private const val ID = "id"
        private const val TITLE = "title"
        private const val AUTHOR = "author"
        private const val ARTWORK = "artwork"
        private const val URIS = "uris"
        private const val PART_TITLES = "partTitles"
        private const val INDEX = "index"
        private const val POSITION = "position"

        /**
         * What separates one part from the next.
         *
         * A newline, because it is the one character a URI cannot contain: `Uri` percent-
         * encodes it, and a title holding one would have arrived from a file name that
         * cannot hold one either. A comma would have been a bug waiting for the first
         * chapter called "Sea Room, Part Two".
         */
        private const val SEPARATOR = "\n"
    }

    /** What was playing, or null when this device has never played a book. */
    fun last(): PlayedBook? {
        val id = preferences.getString(ID, null) ?: return null
        val uris = preferences.getString(URIS, null)?.split(SEPARATOR).orEmpty()
        if (uris.isEmpty() || uris.any { it.isEmpty() }) return null
        val titles = preferences.getString(PART_TITLES, null)?.split(SEPARATOR).orEmpty()
        return PlayedBook(
            id = id,
            title = preferences.getString(TITLE, null).orEmpty(),
            author = preferences.getString(AUTHOR, null),
            artworkUri = preferences.getString(ARTWORK, null),
            uris = uris,
            // Zipped rather than trusted to match: the two lists are written together and
            // read apart, and a title list one short would otherwise throw inside a
            // callback the system is waiting on.
            partTitles = uris.indices.map { titles.getOrNull(it).orEmpty() },
            partIndex = preferences.getInt(INDEX, 0),
            offsetMillis = preferences.getLong(POSITION, 0),
        )
    }

    /** Remembers a book and where it had reached. */
    fun remember(book: Audiobook, partIndex: Int, offsetMillis: Long) {
        preferences.edit().apply {
            putString(ID, book.id)
            putString(TITLE, book.title)
            putString(AUTHOR, book.author)
            putString(ARTWORK, book.artworkUri)
            putString(URIS, book.sources.joinToString(SEPARATOR) { it.uri })
            putString(PART_TITLES, book.sources.joinToString(SEPARATOR) { it.title })
            putInt(INDEX, partIndex)
            putLong(POSITION, offsetMillis)
        }.apply()
    }

    /** Moves the offset of the book already remembered, leaving the rest alone. */
    fun moveTo(publicationId: String, partIndex: Int, offsetMillis: Long) {
        if (preferences.getString(ID, null) != publicationId) return
        preferences.edit().putInt(INDEX, partIndex).putLong(POSITION, offsetMillis).apply()
    }

    /** Forgets it. The listener closed the book, or it ran out. */
    fun forget() {
        preferences.edit().clear().apply()
    }
}

/**
 * A book the system may be asked to put back, with no library behind it.
 *
 * Deliberately not an [Audiobook] plus a [PlaybackPosition]: this is what came out of a
 * preferences file, and keeping it apart is what stops a stale copy of a folder being
 * mistaken for the library's own answer. The app rebuilds a real [Audiobook] when the
 * listener opens the publication properly.
 */
internal data class PlayedBook(
    val id: String,
    val title: String,
    val author: String?,
    val artworkUri: String?,
    val uris: List<String>,
    val partTitles: List<String>,
    val partIndex: Int,
    val offsetMillis: Long,
) {
    /** What a listener is in the middle of, for the row a car or a carousel draws. */
    val partTitle: String get() = partTitles.getOrNull(partIndex).orEmpty()
}
