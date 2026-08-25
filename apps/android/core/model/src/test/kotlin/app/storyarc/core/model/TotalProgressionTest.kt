package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * How far through a book a position is.
 *
 * `ebook-reader` asks for progress as a percentage and forbids presenting a reflowable
 * page number as an identity, so an approximation is allowed and a wrong number is not.
 * iOS's `TotalProgressionTests` asserts the same table.
 */
class TotalProgressionTest {

    @Test
    fun `A reported zero that the position contradicts is not a report`() {
        // The defect this exists for: in scroll mode Readium answers 0.0 rather than
        // nothing, so a reader watched "0% read" while scrolling through chapter one.
        assertEquals(0.37, TotalProgression.resolve(0.0, 0.74, 0, 2), 0.0001)
    }

    @Test
    fun `A reported zero at the very start is trusted, because nothing contradicts it`() {
        assertEquals(0.0, TotalProgression.resolve(0.0, 0.0, 0, 2), 0.0001)
    }

    @Test
    fun `A real report wins over the estimate, because the renderer knows more`() {
        // The renderer has a positions list; the estimate assumes every resource is the
        // same length, which no book is.
        assertEquals(0.9, TotalProgression.resolve(0.9, 0.1, 0, 10), 0.0001)
    }

    @Test
    fun `With no report the estimate stands in, placing the resource then the offset`() {
        assertEquals(0.875, TotalProgression.resolve(null, 0.5, 3, 4), 0.0001)
    }

    @Test
    fun `An unknown resource yields zero rather than a guess`() {
        // A negative index means the href did not match the reading order, and inventing
        // a percentage from that would be worse than admitting to nothing.
        assertEquals(0.0, TotalProgression.resolve(null, 0.5, -1, 4), 0.0001)
        assertEquals(0.0, TotalProgression.resolve(null, 0.5, 0, 0), 0.0001)
    }

    @Test
    fun `Nothing escapes zero to one, whatever the renderer says`() {
        assertEquals(1.0, TotalProgression.resolve(1.4, 0.0, 0, 1), 0.0001)
        assertEquals(0.0, TotalProgression.resolve(-0.2, 0.0, 0, 1), 0.0001)
        assertEquals(1.0, TotalProgression.resolve(null, 3.0, 1, 2), 0.0001)
    }
}
