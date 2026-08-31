package app.storyarc.core.playback

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What a container's chapter marks become, and what an unchaptered book gets instead.
 *
 * `publication-formats`: "an unchaptered audiobook is a normal audiobook", and
 * `audio-playback`: "a publication with no chapter markers lists its parts in playing
 * order instead, rather than showing an empty list". Both come down to one rule — the
 * answer is never empty — and it is asserted here rather than on a device, which is the
 * whole reason [ChapterMark] exists instead of media3's own `Chapter`.
 *
 * iOS's `AudiobookChaptersTests` asserts the same cases against `AVAsset`'s groups.
 */
class AudiobookChaptersTest {

    private val three = listOf(
        ChapterMark("One", 0, 2_000),
        ChapterMark("Two", 2_000, 4_000),
        ChapterMark("Three", 4_000, 6_000),
    )

    @Test
    fun `a chaptered book plays its chapters`() {
        // The corpus's `chaptered.m4b` and `id3-chapters.mp3`: the same three, from two
        // containers that fail differently.
        val parts = AudiobookChapters.parts(three, totalMillis = 6_000, fallbackTitle = "Sea Room")
        assertEquals(listOf("One", "Two", "Three"), parts.map { it.title })
        assertEquals(
            listOf(2_000L, 2_000L, 2_000L),
            parts.map { it.duration.statedMillis },
        )
    }

    @Test
    fun `an unchaptered book is one part, not none`() {
        // The whole of the file standing in for a chapter, named for the publication —
        // which is the only name a listener would recognise. An empty list here is the
        // "empty chapter list" the spec forbids by name.
        val parts = AudiobookChapters.parts(emptyList(), totalMillis = 5_000, fallbackTitle = "Sea Room")
        assertEquals(listOf("Sea Room"), parts.map { it.title })
        assertEquals(5_000L, parts.single().duration.statedMillis)
    }

    @Test
    fun `an unchaptered book of unknown length still opens`() {
        val parts = AudiobookChapters.parts(emptyList(), totalMillis = null, fallbackTitle = "Sea Room")
        assertEquals(PlaybackDuration.Unknown, parts.single().duration)
    }

    @Test
    fun `marks arrive in whatever order and play in theirs`() {
        val parts = AudiobookChapters.parts(three.reversed(), 6_000, "Sea Room")
        assertEquals(listOf("One", "Two", "Three"), parts.map { it.title })
    }

    @Test
    fun `an untitled mark is numbered rather than blank`() {
        val parts = AudiobookChapters.parts(
            listOf(
                ChapterMark(null, 0, 2_000),
                ChapterMark("  ", 2_000, 4_000),
            ),
            totalMillis = 4_000,
            fallbackTitle = "Sea Room",
        )
        assertEquals(listOf("Chapter 1", "Chapter 2"), parts.map { it.title })
    }

    @Test
    fun `the reader's own word for a chapter is used`() {
        // The module ships no resources, so the word arrives from the app. Without this a
        // French reader would get "Chapter 1" between two translated rows.
        val parts = AudiobookChapters.parts(
            listOf(ChapterMark(null, 0, 2_000)),
            totalMillis = 2_000,
            fallbackTitle = "Sea Room",
            chapterWord = "Chapitre",
        )
        assertEquals(listOf("Chapitre 1"), parts.map { it.title })
    }

    @Test
    fun `a hidden mark is not a part`() {
        val parts = AudiobookChapters.parts(
            three.mapIndexed { index, mark -> mark.copy(isHidden = index == 1) },
            totalMillis = 6_000,
            fallbackTitle = "Sea Room",
        )
        assertEquals(listOf("One", "Three"), parts.map { it.title })
    }

    @Test
    fun `a mark describing no audio is dropped`() {
        // A zero-length or backwards mark is a row nothing can play and nothing can seek
        // to. Some encoders write one at the end of a file.
        val parts = AudiobookChapters.parts(
            three + ChapterMark("Tail", 6_000, 6_000) + ChapterMark("Backwards", 5_000, 4_000),
            totalMillis = 6_000,
            fallbackTitle = "Sea Room",
        )
        assertEquals(listOf("One", "Two", "Three"), parts.map { it.title })
    }

    @Test
    fun `offsets are index-aligned with the parts`() {
        // A folder's parts are separate items and the player moves between them itself; a
        // chaptered M4B is one item, so moving to a chapter is a seek — and something has
        // to say where to. Aligned by construction, which is what this pins.
        assertEquals(listOf(0L, 2_000L, 4_000L), AudiobookChapters.offsets(three))
        assertEquals(
            AudiobookChapters.parts(three, 6_000, "Sea Room").size,
            AudiobookChapters.offsets(three).size,
        )
    }

    @Test
    fun `offsets drop the same marks the parts do`() {
        val marks = three.mapIndexed { index, mark -> mark.copy(isHidden = index == 1) }
        assertEquals(listOf(0L, 4_000L), AudiobookChapters.offsets(marks))
        assertEquals(
            AudiobookChapters.parts(marks, 6_000, "Sea Room").size,
            AudiobookChapters.offsets(marks).size,
        )
    }

    @Test
    fun `a position falls in the chapter it is inside`() {
        val offsets = AudiobookChapters.offsets(three)
        assertEquals(0, AudiobookChapters.partAt(offsets, 0))
        assertEquals(0, AudiobookChapters.partAt(offsets, 1_999))
        assertEquals(1, AudiobookChapters.partAt(offsets, 2_000))
        assertEquals(2, AudiobookChapters.partAt(offsets, 5_999))
        // Past the end of the last mark is still the last chapter, not nothing.
        assertEquals(2, AudiobookChapters.partAt(offsets, 60_000))
        // And an unchaptered book is always in its one part.
        assertEquals(0, AudiobookChapters.partAt(emptyList(), 60_000))
    }
}
