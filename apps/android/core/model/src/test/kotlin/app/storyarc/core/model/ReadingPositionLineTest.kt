package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * That a reflowable publication says where the reader is in words, and never in pages.
 *
 * `ebook-reader`, *Progress display* and *A publication that declares no chapters*:
 *
 * > **THEN** one line states how far through the publication they are and how much of the
 * > current chapter is left, in words
 * > …
 * > **THEN** the line states progress through the publication alone rather than naming a
 * > chapter that does not exist
 * > **AND** it does not fall back to a page count, because that is the identity the app
 * > refuses to present
 *
 * iOS mirrors this suite as `ReadingPositionLineTests`, case for case, the way the format
 * layer's suites already do — the two readers must say the same thing about the same book.
 */
class ReadingPositionLineTest {

    @Test
    fun `the percentage is the whole publication, rounded, and clamped to its ends`() {
        assertEquals(0, line(0.0).percentThrough)
        assertEquals(42, line(0.424).percentThrough)
        assertEquals(43, line(0.425).percentThrough)
        assertEquals(100, line(1.0).percentThrough)
        // A renderer that reports past the end is not a reason to show 140%.
        assertEquals(100, line(1.4).percentThrough)
        assertEquals(0, line(-0.2).percentThrough)
    }

    @Test
    fun `a publication that declares no chapters names none, and offers no page count`() {
        val position = ReadingPositionLine.of(
            totalProgression = 0.3,
            chapter = null,
            withinChapter = 0.5,
        )

        assertNull(position.chapter)
        assertNull(position.chapterRemainder)
        assertEquals(30, position.percentThrough)
    }

    @Test
    fun `a blank chapter title is no chapter, because Readium reports both`() {
        for (blank in listOf("", "   ", "\n")) {
            val position = ReadingPositionLine.of(
                totalProgression = 0.3,
                chapter = blank,
                withinChapter = 0.5,
            )
            assertNull("\"$blank\" is not a chapter title", position.chapter)
            assertNull(position.chapterRemainder)
        }
    }

    @Test
    fun `a chapter is named as the publication spells it, without its surrounding space`() {
        val position = ReadingPositionLine.of(
            totalProgression = 0.3,
            chapter = "  Chapter Three  ",
            withinChapter = 0.5,
        )

        assertEquals("Chapter Three", position.chapter)
    }

    @Test
    fun `a chapter with no within-chapter report is named and says nothing more`() {
        val position = ReadingPositionLine.of(
            totalProgression = 0.3,
            chapter = "Chapter Three",
            withinChapter = null,
        )

        assertEquals("Chapter Three", position.chapter)
        assertNull(position.chapterRemainder)
    }

    /**
     * The bands, measured on what is *left* rather than on what is read.
     *
     * Written as a table because the inversion is the mistake this is guarding: a threshold
     * table against the other quantity passes every boundary test and says the opposite thing
     * on every page.
     */
    @Test
    fun `how much of the chapter is left, in bands`() {
        val expected = listOf(
            0.0 to ChapterRemainder.JUST_BEGUN,
            0.05 to ChapterRemainder.JUST_BEGUN,
            0.1 to ChapterRemainder.JUST_BEGUN,
            0.15 to ChapterRemainder.MORE_THAN_HALF_LEFT,
            0.3 to ChapterRemainder.MORE_THAN_HALF_LEFT,
            0.4 to ChapterRemainder.ABOUT_HALF_LEFT,
            0.5 to ChapterRemainder.ABOUT_HALF_LEFT,
            0.6 to ChapterRemainder.ABOUT_HALF_LEFT,
            0.61 to ChapterRemainder.LESS_THAN_HALF_LEFT,
            0.85 to ChapterRemainder.LESS_THAN_HALF_LEFT,
            0.9 to ChapterRemainder.NEARLY_DONE,
            1.0 to ChapterRemainder.NEARLY_DONE,
        )

        for ((within, band) in expected) {
            assertEquals("within $within", band, ChapterRemainder.of(within))
        }
    }

    @Test
    fun `a within-chapter report outside the range still lands in a band`() {
        assertEquals(ChapterRemainder.JUST_BEGUN, ChapterRemainder.of(-1.0))
        assertEquals(ChapterRemainder.NEARLY_DONE, ChapterRemainder.of(3.0))
    }

    private fun line(total: Double) = ReadingPositionLine.of(
        totalProgression = total,
        chapter = null,
        withinChapter = null,
    )
}
