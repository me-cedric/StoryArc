package app.storyarc.core.playback

import app.storyarc.core.model.ReadingPosition
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * One unit for a chaptered single file, over each reader that divides by a part's length.
 *
 * `PartLayout.MARKS` is the shape most audiobooks arrive in: one file with chapter marks
 * inside it. The decoder there knows one number — the time into the file — and every reader
 * of a position wants the time into the *chapter*. While the two were the same field, the
 * stored fraction saturated at 1.0 from the second chapter on, and a ten-chapter M4B was
 * marked finished the instant chapter ten began.
 *
 * The five readers, each asserted below against a real [AudiobookSource]:
 *
 * 1. the stored fraction — `ReadingPosition.Listening.fraction`,
 * 2. the finished rule, which is that fraction against a threshold,
 * 3. the chapter remainder — [NowPlaying.leftInPartMillis],
 * 4. the scrub rail — [NowPlaying.offsetInPartMillis] and back through `positionInPart`,
 * 5. the sleep timer's *end of chapter* — [SleepTimer.of].
 *
 * `ListenedPosition` in `:app` builds the `Listening` case from a position and its parts;
 * the two lines it adds are repeated here because that object cannot be reached from this
 * module, and `ListenedPositionTest` asserts the same numbers through it.
 *
 * Robolectric because `MediaItem.Builder.setUri(String)` reaches `Uri.parse`. Nothing here
 * decodes audio.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class MarksPositionTest {

    /** Ten chapters of one minute each, inside one file. */
    private val chaptered = Audiobook(
        id = "path:/books/sea-room.m4b",
        title = "Sea Room",
        sources = listOf(Audiobook.AudioPart("file:///books/sea-room.m4b", "Sea Room")),
    )

    private val marks = (0 until TEN).map { index ->
        Triple("Chapter ${index + 1}", index * MINUTE, (index + 1) * MINUTE)
    }

    /** A source with the container read, which is when the marks exist. */
    private fun opened(player: FakePlayer, from: PlaybackPosition? = null): AudiobookSource {
        val source = AudiobookSource(chaptered, player)
        source.prepare(from)
        player.measureFile(TEN * MINUTE)
        player.describeChapters(*marks.toTypedArray())
        return source
    }

    private fun stored(source: AudiobookSource): ReadingPosition.Listening =
        ReadingPosition.Listening(
            part = source.position.partIndex,
            partCount = source.parts.size,
            offsetMillis = source.position.offsetMillis,
            ofMillis = source.parts.getOrNull(source.position.partIndex)?.duration?.statedMillis,
        )

    @Test
    fun `a position in a chaptered file is measured from its chapter`() {
        val player = FakePlayer()
        val source = opened(player)

        player.reach(MINUTE + 15_000)

        assertEquals(PlaybackPosition(1, 15_000), source.position)
        assertEquals(MINUTE, source.partStartMillis)
    }

    @Test
    fun `the first chapter of a chaptered file is unchanged`() {
        val player = FakePlayer()
        val source = opened(player)

        player.reach(20_000)

        assertEquals(PlaybackPosition(0, 20_000), source.position)
    }

    @Test
    fun `a file with no marks at all is one part measured from zero`() {
        val player = FakePlayer()
        val source = AudiobookSource(chaptered, player)
        source.prepare()
        player.measureFile(TEN * MINUTE)

        player.reach(400_000)

        assertEquals(PlaybackPosition(0, 400_000), source.position)
    }

    // MARK: reader one, the fraction that goes into the store

    @Test
    fun `the start of the second chapter is one tenth through the book`() {
        val player = FakePlayer()
        val source = opened(player)

        player.reach(MINUTE)

        assertEquals(0.1, stored(source).fraction, 0.0001)
    }

    @Test
    fun `the middle of the second chapter is between the two marks`() {
        val player = FakePlayer()
        val source = opened(player)

        player.reach(MINUTE + 30_000)

        assertEquals(0.15, stored(source).fraction, 0.0001)
    }

    // MARK: reader two, the finished rule

    @Test
    fun `the start of the last chapter does not finish the book`() {
        val player = FakePlayer()
        val source = opened(player)

        player.reach(9 * MINUTE)

        assertFalse("chapter ten has only begun", stored(source).fraction >= FINISHED)
    }

    @Test
    fun `the end of the last chapter finishes the book`() {
        val player = FakePlayer()
        val source = opened(player)

        player.reach(TEN * MINUTE)

        assertTrue(stored(source).fraction >= FINISHED)
    }

    // MARK: reader three, the chapter's own remainder

    @Test
    fun `a chapter states how much of itself is left`() {
        val player = FakePlayer()
        val source = opened(player)
        player.reach(MINUTE + 20_000)

        assertEquals(40_000L, NowPlaying.of(source).leftInPartMillis)
    }

    // MARK: reader four, the scrub rail

    @Test
    fun `a scrub reads and writes the same place`() {
        val player = FakePlayer()
        val source = opened(player)
        player.reach(2 * MINUTE + 10_000)

        val playing = NowPlaying.of(source)

        assertEquals(10_000L, playing.offsetInPartMillis)
        assertEquals(PlaybackPosition(2, 45_000), playing.positionInPart(45_000))
    }

    @Test
    fun `a scrub lands where the rail said`() {
        val player = FakePlayer()
        val source = opened(player)
        player.reach(2 * MINUTE + 10_000)

        source.seek(NowPlaying.of(source).positionInPart(45_000))

        assertEquals(PlaybackPosition(2, 45_000), source.position)
        assertEquals(2 * MINUTE + 45_000, player.currentPosition)
    }

    // MARK: reader five, the sleep timer's end of chapter

    @Test
    fun `end of chapter counts down that chapter and not the file`() {
        val player = FakePlayer()
        val source = opened(player)
        player.reach(MINUTE + 20_000)

        val timer = SleepTimer.of(SleepAfter.EndOfChapter, NowPlaying.of(source))

        assertEquals(40_000L, timer?.remainingMillis)
    }

    // MARK: what the decoder is handed back

    /**
     * The one reader that wants a time into the item rather than into the chapter.
     *
     * `PlaybackHost` writes it to `PlaybackMemory`, and a service the system restarts hands
     * it to media3 with no chapter marks read. A part offset stored there would put a
     * ten-chapter book back at the start of the file.
     */
    @Test
    fun `the record a restarted service resumes from is a time into the file`() {
        val player = FakePlayer()
        val source = opened(player)
        player.reach(3 * MINUTE + 25_000)

        assertEquals(3 * MINUTE + 25_000, NowPlaying.of(source).itemTimeMillis)
    }

    // MARK: what the store hands back

    @Test
    fun `a stored place in a later chapter starts inside that chapter`() {
        val player = FakePlayer()

        // What `ListenedPosition.resume` produces: the fourth chapter, twenty seconds in.
        val source = opened(player, from = PlaybackPosition(3, 20_000))

        assertEquals(PlaybackPosition(3, 20_000), source.position)
        assertEquals(3 * MINUTE + 20_000, player.currentPosition)
    }

    @Test
    fun `a chapter chosen from the page starts at that chapter`() {
        val player = FakePlayer()

        // What `AppHost.listenFrom` produces for a chosen row.
        val source = opened(player, from = PlaybackPosition(5, 0))

        assertEquals(PlaybackPosition(5, 0), source.position)
        assertEquals(5 * MINUTE, player.currentPosition)
    }

    @Test
    fun `a stored place in the first chapter needs no marks to be right`() {
        val player = FakePlayer()
        val source = AudiobookSource(chaptered, player)

        source.prepare(PlaybackPosition(0, 20_000))

        assertEquals(20_000L, player.currentPosition)
        assertEquals(PlaybackPosition(0, 20_000), source.position)
    }

    @Test
    fun `a second reading of the marks does not move the audio again`() {
        val player = FakePlayer()
        val source = opened(player, from = PlaybackPosition(3, 20_000))
        player.reach(4 * MINUTE)

        // media3 reports tracks more than once — a format change, a period change.
        player.describeChapters(*marks.toTypedArray())

        assertEquals(PlaybackPosition(4, 0), source.position)
    }

    private companion object {
        const val MINUTE = 60_000L
        const val TEN = 10

        /** `ListenedPosition.FINISHED`, which is `:app`'s and not reachable from here. */
        const val FINISHED = 0.999
    }
}
