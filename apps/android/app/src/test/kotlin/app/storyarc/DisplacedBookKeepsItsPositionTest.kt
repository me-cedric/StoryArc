package app.storyarc

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.playback.PlaybackDuration
import app.storyarc.core.playback.PlaybackHost
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * `audiobooks-and-playback` 6.1, wave 5 defect 1: a book another source displaces began again
 * at the start. [PlayingBook.play] points the writer at the new book before the host starts
 * it, and the host writes the outgoing book's position while it starts the new one.
 *
 * Driven through the hook [PlayingBook] hands the host, in the order `play` and the host use.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37.
@Config(sdk = [34])
class DisplacedBookKeepsItsPositionTest {

    private fun book(path: String) = Publication(
        identity = PublicationIdentity(normalizedPath = path),
        format = PublicationFormat.M4B,
        displayTitle = path,
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private val cover = book("/with-cover-long")
    private val sea = book("/sea-room")
    private val parts = listOf(PlaybackPart("One", PlaybackDuration.Known(300_000)))

    private lateinit var store: ProgressStore

    @Before
    fun open() {
        store = ProgressStore.inMemory(ApplicationProvider.getApplicationContext())
    }

    @After
    fun close() {
        PlaybackHost.recordPosition = null
    }

    private fun stored(book: Publication): ReadingProgress? {
        repeat(200) {
            shadowOf(Looper.getMainLooper()).idle()
            runBlocking { store.progress(book.identity) }?.let { return it }
            Thread.sleep(25)
        }
        return runBlocking { store.progress(book.identity) }
    }

    @Test
    fun `the book the next one displaces is written where it stopped`() {
        PlayingBook.follow(cover, store)
        // What `play` does first, before the host displaces the outgoing book.
        PlayingBook.follow(sea, store)

        PlaybackHost.recordPosition!!.invoke(cover.id, PlaybackPosition(0, 75_000), parts, false)

        val record = stored(cover)
        assertNotNull("the displaced book's position was dropped", record)
        assertEquals(ReadingPosition.Listening(0, 1, 75_000, 300_000), record!!.position)
    }

    @Test
    fun `a book the app never started is still not written`() {
        PlayingBook.follow(sea, store)
        val stranger = book("/never-played")

        PlaybackHost.recordPosition!!.invoke(stranger.id, PlaybackPosition(0, 5_000), parts, false)
        shadowOf(Looper.getMainLooper()).idle()

        assertNull(runBlocking { store.progress(stranger.identity) })
    }
}
