package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What one more page does to a source's continued read.
 *
 * `sources`' *More from a source than the library holds*: the source detail states the
 * progress while a read continues, and stops claiming a total once it has one. Every case
 * here is the whole of what decides that. `KavitaContinuedReadTest` asserts the loop that
 * asks it. iOS's `SourceReadProgressTests` asks the same three questions.
 */
class SourceReadProgressTest {

    @Test
    fun `a fresh source starts at page two, with the first slice already counted`() {
        val progress = SourceReadProgress.started(firstSliceRead = 60)

        assertEquals(60, progress.read)
        assertEquals(null, progress.total)
        assertEquals(2, progress.nextPage)
    }

    @Test
    fun `a full page keeps the read going, past the page it just answered`() {
        val progress = SourceReadProgress(read = 60, total = 215, nextPage = 2)

        val step = progress.advancing(pageRequested = 2, unitsRead = 60, holdsMore = true)

        assertEquals(
            SourceReadStep.Continuing(SourceReadProgress(read = 120, total = 215, nextPage = 3)),
            step,
        )
    }

    @Test
    fun `a short page ends the read, with what it added still counted`() {
        val progress = SourceReadProgress(read = 120, total = 215, nextPage = 3)

        val step = progress.advancing(pageRequested = 3, unitsRead = 34, holdsMore = false)

        assertEquals(
            SourceReadStep.Finished(SourceReadProgress(read = 154, total = 215, nextPage = 4)),
            step,
        )
    }

    @Test
    fun `a page that is not the one waited on changes nothing`() {
        // Two readers of the same source overlapping -- a pull-to-refresh landing while a
        // continuation is already past page two. The second one's answer for a page
        // already left behind must not be folded in on top of the one that came after it.
        val progress = SourceReadProgress(read = 180, total = 215, nextPage = 4)

        val step = progress.advancing(pageRequested = 2, unitsRead = 60, holdsMore = true)

        assertEquals(SourceReadStep.Stale, step)
    }
}
