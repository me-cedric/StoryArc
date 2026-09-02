package app.storyarc.core.playback

import androidx.media3.common.MediaMetadata
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What the system is handed when it asks what the listener was in the middle of.
 *
 * `MediaSession.Callback.onPlaybackResumption`, and `onSetMediaItems` when a car presses
 * play on the browsed row. Both answer from [PlaybackMemory], and both have to name the
 * place the row named — a listener who presses play on "Chapter 4" and gets chapter 1 is
 * the failure this callback exists to prevent.
 *
 * **What these cases can and cannot prove.** They prove that the position handed back is the
 * position that was saved, and that a memory older than the book it names cannot throw
 * inside a callback the system is waiting on. They do **not** prove that the carousel comes
 * back after process death: that needs the process killed between two runs, on a device, and
 * it has not been done.
 *
 * Robolectric because `MediaItem.Builder.setUri(String)` calls `Uri.parse`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PlaybackResumptionTest {

    private val book = PlayedBook(
        id = "path:/books/sea-room",
        title = "Sea Room",
        author = "Adam Nicolson",
        artworkUri = "file:///books/sea-room/cover.jpg",
        uris = listOf(
            "file:///books/sea-room/01.mp3",
            "file:///books/sea-room/02.mp3",
            "file:///books/sea-room/03.mp3",
        ),
        partTitles = listOf("The Shiants", "Bird Island", "The Fank"),
        partIndex = 2,
        offsetMillis = 91_000,
    )

    @Test
    fun `the place it starts is the place that was saved`() {
        val resumption = PlaybackResumption.of(book)

        assertEquals(2, resumption.startIndex)
        assertEquals(91_000, resumption.startPositionMs)
        assertEquals(3, resumption.items.size)
    }

    /**
     * A folder re-downloaded with fewer files leaves an index past the end.
     *
     * media3 throws on an index it cannot honour, and it would throw inside a callback the
     * system is already showing a row for.
     */
    @Test
    fun `a part index the book no longer has is clamped rather than thrown`() {
        val shorter = book.copy(uris = book.uris.take(2), partTitles = book.partTitles.take(2))

        assertEquals(1, PlaybackResumption.of(shorter).startIndex)
    }

    @Test
    fun `a book with nothing in it starts at zero rather than at minus one`() {
        val empty = book.copy(uris = emptyList(), partTitles = emptyList())

        assertEquals(0, PlaybackResumption.of(empty).startIndex)
        assertEquals(0, PlaybackResumption.of(empty).items.size)
    }

    @Test
    fun `a negative offset is clamped to the start`() {
        assertEquals(0, PlaybackResumption.of(book.copy(offsetMillis = -5)).startPositionMs)
    }

    /**
     * Every item names the publication and the **chapter**, which is what the lock screen
     * and the shade draw on their two lines.
     */
    @Test
    fun `each item carries the book's title and its own part's name`() {
        val items = PlaybackResumption.of(book).items

        assertEquals("Sea Room", items[1].mediaMetadata.title)
        assertEquals("Bird Island", items[1].mediaMetadata.subtitle)
        assertEquals("Adam Nicolson", items[1].mediaMetadata.artist)
        assertEquals(
            MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER,
            items[1].mediaMetadata.mediaType,
        )
    }

    /** A title list shorter than the URI list is a gap, not a crash. */
    @Test
    fun `a part with no remembered name still produces an item`() {
        val ragged = book.copy(partTitles = listOf("The Shiants"))

        val items = PlaybackResumption.of(ragged).items

        assertEquals(3, items.size)
        assertEquals("", items[2].mediaMetadata.subtitle)
    }

    /** The ids are the book's and the file's, so a browsed row resolves back to one book. */
    @Test
    fun `each item is identified by the book and its own file`() {
        val items = PlaybackResumption.of(book).items

        assertEquals("path:/books/sea-room:file:///books/sea-room/01.mp3", items[0].mediaId)
    }
}
