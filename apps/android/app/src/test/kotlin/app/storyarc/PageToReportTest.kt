package app.storyarc

import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.persistence.KavitaOrigin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The page number a recorded position reports to Kavita.
 *
 * The field report: an EPUB read from Kavita never pushed its position -- [ReaderHost]'s
 * report closure recognised only [ReadingPosition.Page], so a reflowable position was
 * dropped silently on every close. iOS's `KavitaOriginPageToReportTests` asserts the same
 * cases.
 */
class PageToReportTest {

    private fun origin(pages: Int) =
        KavitaOrigin(sourceId = "s", libraryId = 1, seriesId = 7, volumeId = 3, chapterId = 42, pages = pages)

    @Test
    fun `a paged position reports its own index, ignoring the chapter's page count`() {
        assertEquals(3, pageToReport(ReadingPosition.Page(3, 10), origin(pages = 0)))
    }

    @Test
    fun `a reflowable position becomes a page, from the chapter's own length`() {
        assertEquals(10, pageToReport(ReadingPosition.Reflowable(0.5, "{}"), origin(pages = 21)))
    }

    @Test
    fun `a reflowable position with no known page count is not reported`() {
        assertNull(pageToReport(ReadingPosition.Reflowable(0.5, "{}"), origin(pages = 0)))
    }

    @Test
    fun `a listening position takes the same rule as a reflowable one`() {
        val listening = ReadingPosition.Listening(part = 1, partCount = 2, offsetMillis = 0, ofMillis = null)
        assertEquals(10, pageToReport(listening, origin(pages = 21)))
    }
}
