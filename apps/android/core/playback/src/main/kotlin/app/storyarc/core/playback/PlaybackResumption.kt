package app.storyarc.core.playback

import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

/**
 * A remembered book, turned into what the system needs to put it back on the air.
 *
 * `MediaSession.Callback.onPlaybackResumption` is what makes the notification-shade carousel
 * work after process death: the system starts the service *without* the app, asks what the
 * listener was in the middle of, and shows nothing at all if the answer is nothing. This is
 * the answer, built out of [PlaybackMemory]'s handful of strings.
 *
 * **Out of [PlaybackService] so that it can be asserted.** Proving the carousel end to end
 * needs the process killed between two runs, which is a device exercise; proving that the
 * position handed back is the position that was saved does not, and it is the half that
 * would be silently wrong. `onSetMediaItems` — what a car sends when a listener presses play
 * on the browsed row — builds its answer here too, which is what makes "carrying on" and
 * "resuming" the same place rather than two nearly identical calculations.
 */
internal object PlaybackResumption {

    fun of(book: PlayedBook): PlaybackService.Resumption = PlaybackService.Resumption(
        items = book.uris.mapIndexed { index, uri -> item(book, index, uri) },
        // **Clamped, because a memory can be older than the book it names.** A folder
        // re-downloaded with fewer files leaves an index past the end, and an index media3
        // cannot honour throws inside a callback the system is waiting on.
        startIndex = book.partIndex.coerceIn(0, (book.uris.size - 1).coerceAtLeast(0)),
        startPositionMs = book.offsetMillis.coerceAtLeast(0),
    )

    private fun item(book: PlayedBook, index: Int, uri: String): MediaItem = MediaItem.Builder()
        .setUri(uri)
        .setMediaId("${book.id}:$uri")
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(book.title)
                // The **chapter**, not the file. A product decision, recorded as one in
                // `design.md`, and this is the line the lock screen and the shade draw
                // under the title.
                .setSubtitle(book.partTitles.getOrNull(index).orEmpty())
                .setArtist(book.author)
                .setArtworkUri(book.artworkUri?.let(Uri::parse))
                .setIsBrowsable(false)
                .setIsPlayable(true)
                .setMediaType(MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER)
                .build(),
        )
        .build()
}
