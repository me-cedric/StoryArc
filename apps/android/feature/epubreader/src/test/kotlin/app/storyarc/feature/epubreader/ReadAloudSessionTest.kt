package app.storyarc.feature.epubreader

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.playback.PauseCause
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What only a voice has, and the one thing it borrows.
 *
 * **The pause table is no longer here.** What a pause means, what the end of an
 * interruption does to it, and what opening a second publication does are
 * `:core:playback`'s `PlaybackSession` and `SessionHandover`, asserted in
 * `PlaybackSessionTest`. `audio-playback` asks the same question of a narrated file and
 * answers it the same way, so read-aloud reads that table rather than keeping a second
 * copy — and the first case below is what pins that it does.
 *
 * What stays is what a synthesised voice has and a narrated file does not: the line the
 * transport says, and the position a spoken sentence makes. iOS keeps the same split.
 */
class ReadAloudSessionTest {

    /**
     * Read-aloud's session **is** the player's session.
     *
     * A type assertion rather than a behaviour one, and it is the point of the change: two
     * session types would let a narrated book and a spoken one drift apart on the one
     * question — whether a finished phone call starts the book again — that both specs
     * answer identically.
     */
    @Test
    fun `read-aloud drives the shared playback session`() {
        val speaking: PlaybackSession = PlaybackSession().started()
        assertTrue(speaking.isPlaying)
        assertEquals(PlaybackState.PLAYING, speaking.state)
        assertEquals(PauseCause.LISTENER, speaking.pausedByListener().pausedBy)
    }

    @Test
    fun `the lock screen names the chapter under the title`() {
        val label = SpokenLabel.of("Sea Room", "Chapter Two", "Adam Nicolson")
        assertEquals("Sea Room", label.title)
        assertEquals("Chapter Two", label.detail)
    }

    @Test
    fun `a book with no navigation falls back to its author`() {
        assertEquals("Adam Nicolson", SpokenLabel.of("Sea Room", null, "Adam Nicolson").detail)
        assertEquals("Adam Nicolson", SpokenLabel.of("Sea Room", "  ", "Adam Nicolson").detail)
    }

    @Test
    fun `a book with neither says only its title`() {
        assertEquals(null, SpokenLabel.of("Sea Room", null, null).detail)
        assertEquals(null, SpokenLabel.of("Sea Room", "", " ").detail)
    }

    // Where the listening got to.

    private val sentence = """{"href":"/chapter-4.xhtml","type":"text/html"}"""
    private val identity = PublicationIdentity(normalizedPath = "/books/sea-room.epub")
    private val moment = 1_700_000_000_000L

    /**
     * The path that can lose an hour. What the session hands the progress store is the
     * sentence the voice reached, as an opaque locator — never a page number, which a
     * reflowable book does not have.
     */
    @Test
    fun `the reached position is recorded as the sentence, not as a page`() {
        val record = ReachedPosition(sentence, progression = 0.42).record(identity, moment)
        assertEquals(identity, record.identity)
        assertEquals(ReadingPosition.Reflowable(0.42, sentence), record.position)
        assertEquals(moment, record.updatedAtEpochMillis)
        assertFalse(record.isFinished)
    }

    /** The end of the publication is the end of the content, not a page count. */
    @Test
    fun `listening to the last sentence finishes the book`() {
        assertTrue(ReachedPosition(sentence, 1.0).record(identity, moment).isFinished)
        assertFalse(ReachedPosition(sentence, 0.9989).record(identity, moment).isFinished)
    }

    /**
     * A session the process is reclaimed under writes nothing more, so what was written on
     * the way has to stand on its own — and an empty locator would stand for nothing.
     */
    @Test
    fun `a sentence with no locator is not written over a good position`() {
        assertFalse(ReachedPosition("", progression = 0.42).isRecordable)
        assertTrue(ReachedPosition(sentence, progression = 0.0).isRecordable)
    }
}
