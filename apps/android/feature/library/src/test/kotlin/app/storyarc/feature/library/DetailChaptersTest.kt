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
    fun `a book nobody has started marks nothing`() {
        val rows = chapterRows(three, stoppedIn = null)

        assertTrue(rows.all { it.progress == ChapterProgress.UNPLAYED })
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
