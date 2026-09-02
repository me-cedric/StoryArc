package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A skip through the decoder, and where a folder's part lengths come from.
 *
 * `audio-playback`, *Skipping*: "skipping past the start or the end of a chapter continues
 * into the neighbouring one rather than stopping at the boundary".
 *
 * **The two layouts reach that answer differently, and only one of them needs arithmetic.**
 * A chaptered single file is one continuous item whose offsets are file-wide, so crossing a
 * mark is nothing — the position simply passes it. A folder is a playlist of items with
 * per-item positions, so the offset has to be converted to whole-book time and back, and
 * that needs to know how long the earlier files are. Nothing in the format layer measures
 * them: `OpenedAudiobook` says why, an extractor per file would cost a five-hundred-book
 * library a decode pass per scan. So the decoder is the only source of those lengths, and
 * media3 puts them on a `Timeline`'s windows.
 *
 * Robolectric because `MediaItem.Builder.setUri(String)` calls `Uri.parse`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AudiobookSkipTest {

    private val folder = Audiobook(
        id = "path:/books/sea-room",
        title = "Sea Room",
        sources = listOf(
            Audiobook.AudioPart("file:///books/sea-room/01.mp3", "The Shiants"),
            Audiobook.AudioPart("file:///books/sea-room/02.mp3", "Bird Island"),
            Audiobook.AudioPart("file:///books/sea-room/03.mp3", "The Fank"),
        ),
    )

    private val singleFile = Audiobook(
        id = "path:/books/sea-room.m4b",
        title = "Sea Room",
        sources = listOf(Audiobook.AudioPart("file:///books/sea-room.m4b", "Sea Room")),
    )

    // MARK: where a folder's lengths come from

    @Test
    fun `a folder's parts take their lengths from the timeline`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()

        player.measure(300_000, 420_000, 480_000)

        assertEquals(
            listOf(
                PlaybackDuration.Known(300_000),
                PlaybackDuration.Known(420_000),
                PlaybackDuration.Known(480_000),
            ),
            source.parts.map { it.duration },
        )
        // The names are the format layer's, and the decoder does not get to rename them.
        assertEquals(listOf("The Shiants", "Bird Island", "The Fank"), source.parts.map { it.title })
    }

    @Test
    fun `a file the decoder has not measured stays unmeasured`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()

        player.measure(300_000, -1, 480_000)

        assertEquals(PlaybackDuration.Unknown, source.parts[1].duration)
        assertEquals(PlaybackDuration.Known(300_000), source.parts[0].duration)
    }

    /**
     * A timeline of a different length is not this book's, and is ignored.
     *
     * media3 reports an empty timeline before it has read anything, and adopting that would
     * throw away the names the format layer supplied.
     */
    @Test
    fun `a timeline that does not match the playlist is ignored`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()

        player.measure(300_000)

        assertEquals(listOf("The Shiants", "Bird Island", "The Fank"), source.parts.map { it.title })
        assertEquals(PlaybackDuration.Unknown, source.parts[0].duration)
    }

    /**
     * A single file's parts are its chapter marks, which arrive with the tracks.
     *
     * Its one window is the whole book, so adopting the window duration as *the part's*
     * would give a three-chapter book one part the length of all three.
     */
    @Test
    fun `a single file does not take its parts from the timeline`() {
        val player = FakePlayer()
        val source = AudiobookSource(singleFile, player)
        source.prepare()

        player.measure(1_200_000)

        assertEquals(1, source.parts.size)
        assertEquals("Sea Room", source.parts[0].title)
    }

    // MARK: the boundary

    @Test
    fun `skipping back across a folder's file boundary lands in the previous file`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()
        player.measure(300_000, 420_000, 480_000)
        player.reachPart(1, 5_000)

        source.skip(SkipDirection.BACK, byMillis = 15_000)

        assertEquals(PlaybackPosition(0, 290_000), source.position)
    }

    @Test
    fun `skipping forward across a folder's file boundary lands in the next file`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()
        player.measure(300_000, 420_000, 480_000)
        player.reachPart(0, 290_000)

        source.skip(SkipDirection.FORWARD, byMillis = 30_000)

        assertEquals(PlaybackPosition(1, 20_000), source.position)
    }

    @Test
    fun `skipping back at the start of a folder stays at the start`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()
        player.measure(300_000, 420_000, 480_000)
        player.reachPart(0, 4_000)

        source.skip(SkipDirection.BACK, byMillis = 15_000)

        assertEquals(PlaybackPosition(0, 0), source.position)
    }

    /**
     * An unmeasured folder does not move rather than moving somewhere wrong.
     *
     * The decoder has not read the playlist, so no arithmetic can say where 15 seconds
     * before the start of file two is. Landing at the boundary would be the stop the spec
     * forbids; landing anywhere else would be a guess.
     */
    @Test
    fun `a skip across a boundary the decoder has not measured moves nothing`() {
        val player = FakePlayer()
        val source = AudiobookSource(folder, player)
        source.prepare()
        player.reachPart(1, 5_000)

        source.skip(SkipDirection.BACK, byMillis = 15_000)

        assertEquals(PlaybackPosition(1, 5_000), source.position)
    }

    // MARK: the single file, where the marks are inside one item

    @Test
    fun `a skip inside a single file passes its chapter marks without changing item`() {
        val player = FakePlayer()
        val source = AudiobookSource(singleFile, player)
        source.prepare()
        player.measureFile(1_200_000)
        player.reach(295_000)

        source.skip(SkipDirection.FORWARD, byMillis = 30_000)

        assertEquals(PlaybackPosition(0, 325_000), source.position)
    }

    @Test
    fun `a skip back to before the start of a single file stops at the start`() {
        val player = FakePlayer()
        val source = AudiobookSource(singleFile, player)
        source.prepare()
        player.measureFile(1_200_000)
        player.reach(5_000)

        source.skip(SkipDirection.BACK, byMillis = 15_000)

        assertEquals(PlaybackPosition(0, 0), source.position)
    }

    @Test
    fun `a skip forward past the end of a single file stops at its end`() {
        val player = FakePlayer()
        val source = AudiobookSource(singleFile, player)
        source.prepare()
        player.measureFile(1_200_000)
        player.reach(1_190_000)

        source.skip(SkipDirection.FORWARD, byMillis = 30_000)

        assertEquals(PlaybackPosition(0, 1_200_000), source.position)
    }
}
