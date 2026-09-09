package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What an audiobook's page says about its chapters, decided without a screen.
 *
 * `audio-playback`, *Chapters before the first minute*: the page lists them, marks the one in
 * progress and the ones finished, draws no list for a single-part book, and names the chapter
 * a resume lands inside. Each of those is a decision rather than a layout, so each is asserted
 * here and the composition test asserts that the page draws what these return.
 *
 * iOS answers the same four questions in its own `DetailChapters`.
 */
class DetailChaptersTest {

    private fun part(title: String, millis: Long?) = AudiobookPart(title, millis)

    private val three = listOf(
        part("The Harbour", 120_000),
        part("The Crossing", 300_000),
        part("The Return", 240_000),
    )

    @Test
    fun `every chapter is listed in order with its duration`() {
        val rows = chapterRows(three, stoppedIn = null)

        assertEquals(listOf("The Harbour", "The Crossing", "The Return"), rows.map { it.title })
        assertEquals(listOf(120_000L, 300_000L, 240_000L), rows.map { it.statedMillis })
    }

    @Test
    fun `the chapter stopped inside is in progress and the ones before it are finished`() {
        val rows = chapterRows(three, stoppedIn = 1)

        assertEquals(
            listOf(
                ChapterProgress.FINISHED,
                ChapterProgress.IN_PROGRESS,
                ChapterProgress.UNPLAYED,
            ),
            rows.map { it.progress },
        )
    }

    @Test
    fun `the chapter in progress states how much of itself is left`() {
        // `audio-playback`: the chapter in progress "states how much of itself is left, so a
        // listener can tell a chapter they have just begun from one they are about to
        // finish". Three minutes into a five-minute chapter leaves two.
        val rows = chapterRows(three, stoppedIn = 1, offsetMillis = 180_000)

        assertEquals(120_000L, rows[1].leftMillis)
    }

    @Test
    fun `a chapter the listener has not reached states no remainder`() {
        // All of it is left, which is what its duration already says. A second number on
        // every row would say the same thing three times and mark nothing.
        val rows = chapterRows(three, stoppedIn = 1, offsetMillis = 180_000)

        assertNull(rows[0].leftMillis)
        assertNull(rows[2].leftMillis)
    }

    @Test
    fun `a chapter whose length the container never stated states no remainder`() {
        // A folder audiobook before a decoder has measured it. Nothing is reported as a
        // fault, and a zero would read as a chapter about to end.
        val unmeasured = listOf(part("One", millis = null), part("Two", millis = null))

        val rows = chapterRows(unmeasured, stoppedIn = 1, offsetMillis = 180_000)

        assertNull(rows[1].statedMillis)
        assertNull(rows[1].leftMillis)
    }

    @Test
    fun `a remainder never runs past the end of its chapter`() {
        // A position recorded against a container since re-read with shorter parts. Zero
        // left is honest; a negative clock reads as a chapter owing time.
        val rows = chapterRows(three, stoppedIn = 0, offsetMillis = 500_000)

        assertEquals(0L, rows[0].leftMillis)
    }

    @Test
    fun `a book nobody has started marks nothing`() {
        val rows = chapterRows(three, stoppedIn = null)

        assertTrue(rows.all { it.progress == ChapterProgress.UNPLAYED })
    }

    /**
     * `audio-playback`: "a chapter already finished is marked as finished".
     *
     * A finished publication is the case no saved position describes — it offers to start
     * again, so `ListenedPosition.resume` answers null and `stoppedIn` with it. The page
     * marked every row of a book heard to the end as unplayed, and disagreed with iOS about
     * the same book.
     */
    @Test
    fun `every chapter of a finished book is marked finished`() {
        val rows = chapterRows(three, stoppedIn = null, isFinished = true)

        assertTrue(rows.all { it.progress == ChapterProgress.FINISHED })
    }

    @Test
    fun `a finished book states no remainder on any chapter`() {
        val rows = chapterRows(three, stoppedIn = null, offsetMillis = 60_000, isFinished = true)

        assertTrue(rows.all { it.leftMillis == null })
    }

    /**
     * Finished is sticky, and a listener who starts the book again is still in a chapter.
     *
     * Measured on 2026-09-09: the flag was tested before the place, so every row of the book
     * playing right now was marked finished and no row stated a remainder. The flag answers
     * the case where nothing else can — a finished book nobody is playing — and a place, from
     * the session or from the store, always describes the listener better than it does.
     */
    @Test
    fun `a finished book being heard again is marked from where the audio is`() {
        val rows = chapterRows(three, stoppedIn = 1, offsetMillis = 60_000, isFinished = true)

        assertEquals(ChapterProgress.FINISHED, rows[0].progress)
        assertEquals(ChapterProgress.IN_PROGRESS, rows[1].progress)
        assertEquals(ChapterProgress.UNPLAYED, rows[2].progress)
        assertEquals(240_000L, rows[1].leftMillis)
    }

    @Test
    fun `a single part draws no list and states the whole duration instead`() {
        // `AudiobookChapters.parts` gives an unchaptered book one part standing for the whole
        // file, so one part is exactly the case the spec refuses a list for: "a list of one
        // row tells a listener nothing".
        val one = listOf(part("Sea Room", 5_400_000))

        assertEquals(emptyList<DetailChapter>(), chapterRows(one, stoppedIn = null))
        assertEquals(5_400_000L, wholeBookMillis(one))
    }

    @Test
    fun `a single part whose length nobody knows states no duration`() {
        // Nothing is reported as missing. `publication-formats` opens an unchaptered
        // audiobook without complaint, and a page inventing a total would be worse.
        assertNull(wholeBookMillis(listOf(part("Sea Room", millis = null))))
    }

    @Test
    fun `the resume names the chapter it lands inside`() {
        val inside = resumeChapterTitle(three, stoppedIn = 2)

        assertEquals("The Return", inside)
    }

    @Test
    fun `a book never started names no chapter`() {
        assertNull(resumeChapterTitle(three, stoppedIn = null))
    }

    @Test
    fun `a single-part book names no chapter either`() {
        // Its one part carries the book's own title, so naming it would print the title the
        // reader is already looking at.
        val one = listOf(part("Sea Room", 5_400_000))

        assertNull(resumeChapterTitle(one, stoppedIn = 0))
    }

    @Test
    fun `a position past the last chapter names none rather than throwing`() {
        // A container that has been re-read with fewer marks than the position was recorded
        // against. The page states no chapter rather than failing on the way to a button.
        assertNull(resumeChapterTitle(three, stoppedIn = 9))
    }
}
