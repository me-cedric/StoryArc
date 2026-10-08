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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * `close-the-audited-gaps` 23.6, owner answer O21: a book that ends on a failed part is not
 * recorded as finished. The position stays at the failed part, and the listener may mark the
 * book finished from the screen it ends on.
 *
 * Driven through the hook [PlayingBook] hands the host, with a real in-memory store, because
 * the host's own half (`DamagedBookEndingTest`) already asserts that the flag arrives there.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37.
@Config(sdk = [34])
class DamagedEndMarkTest {

    private val sea = Publication(
        identity = PublicationIdentity(normalizedPath = "/sea-room"),
        format = PublicationFormat.M4B,
        displayTitle = "Sea Room",
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private val parts = listOf(
        PlaybackPart("One", PlaybackDuration.Known(300_000)),
        PlaybackPart("Two", PlaybackDuration.Known(300_000)),
    )

    private lateinit var store: ProgressStore

    @Before
    fun open() {
        store = ProgressStore.inMemory(ApplicationProvider.getApplicationContext())
        PlayingBook.follow(sea, store)
    }

    @After
    fun close() {
        PlaybackHost.recordPosition = null
    }

    private fun reach(position: PlaybackPosition, endedOnFailure: Boolean) {
        PlaybackHost.recordPosition!!.invoke(sea.id, position, parts, endedOnFailure)
    }

    /** The store's answer once the write the hook launched has landed. */
    private fun stored(until: (ReadingProgress) -> Boolean = { true }): ReadingProgress? {
        repeat(200) {
            shadowOf(Looper.getMainLooper()).idle()
            runBlocking { store.progress(sea.identity) }?.takeIf(until)?.let { return it }
            Thread.sleep(25)
        }
        return runBlocking { store.progress(sea.identity) }
    }

    @Test
    fun `a failed last part keeps its position and does not finish the book`() {
        // The very end of the last part, which is the worst case: the rule that finishes a book
        // by position would call it finished.
        reach(PlaybackPosition(1, 300_000), endedOnFailure = true)

        val record = stored()
        assertNotNull(record)
        assertFalse("a damaged ending was recorded as finished", record!!.isFinished)
        assertEquals(ReadingPosition.Listening(1, 2, 300_000, 300_000), record.position)
        assertEquals(DamagedEnd(sea), PlayingBook.damagedEnd.value)
    }

    @Test
    fun `a book that plays to its end is still recorded as finished`() {
        reach(PlaybackPosition(1, 300_000), endedOnFailure = false)

        assertTrue(stored()!!.isFinished)
        assertNull(PlayingBook.damagedEnd.value)
    }

    @Test
    fun `marking it finished sets the flag and keeps the failed part's position`() {
        reach(PlaybackPosition(0, 120_000), endedOnFailure = true)
        stored()

        PlayingBook.markDamagedEndFinished()

        val record = stored { it.isFinished }!!
        assertTrue(record.isFinished)
        val position = record.position as ReadingPosition.Listening
        assertEquals(0, position.part)
        assertEquals(120_000L, position.offsetMillis)
        assertEquals(DamagedEnd(sea, marked = true), PlayingBook.damagedEnd.value)
    }

    @Test
    fun `a stop the listener made offers nothing to mark`() {
        reach(PlaybackPosition(0, 120_000), endedOnFailure = false)
        stored()

        PlayingBook.markDamagedEndFinished()

        assertFalse(stored()!!.isFinished)
        assertNull(PlayingBook.damagedEnd.value)
    }

    @Test
    fun `the next book does not inherit the offer`() {
        reach(PlaybackPosition(0, 120_000), endedOnFailure = true)
        assertNotNull(PlayingBook.damagedEnd.value)

        PlayingBook.follow(sea.copy(identity = PublicationIdentity(normalizedPath = "/long-field")), store)

        assertNull(PlayingBook.damagedEnd.value)
    }
}
