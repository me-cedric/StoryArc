package app.storyarc.feature.reader

import app.storyarc.core.model.Annotation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A page bookmark for a fixed-page publication (D8): the arithmetic and the locator
 * encoding. iOS's `ComicPageBookmarkTests` asserts the same table.
 */
class ComicPageBookmarkTest {

    @Test
    fun `progression walks from 0 at the first page to 1 at the last`() {
        assertEquals(0.0, ComicPageBookmark.progression(0, 5), 0.0)
        assertEquals(1.0, ComicPageBookmark.progression(4, 5), 0.0)
        assertEquals(0.5, ComicPageBookmark.progression(2, 5), 0.0)
    }

    @Test
    fun `a single-page publication reports 0, not a division by zero`() {
        assertEquals(0.0, ComicPageBookmark.progression(0, 1), 0.0)
    }

    @Test
    fun `a bookmark's own locator reads back the page it was made on`() {
        val annotation = Annotation(
            id = "1",
            locator = "12",
            resource = "12",
            progression = 0.5,
            chapter = "",
            text = "Page 13",
            createdAtEpochMillis = 0L,
        )
        assertEquals(12, ComicPageBookmark.pageIndexOf(annotation))
    }

    @Test
    fun `a locator this format did not write reads as no page at all`() {
        val pdfStyleAnnotation = Annotation(
            id = "1",
            locator = """{"page":2,"rects":[]}""",
            resource = "3",
            progression = 0.5,
            chapter = "",
            text = "some words",
            createdAtEpochMillis = 0L,
        )
        assertNull(ComicPageBookmark.pageIndexOf(pdfStyleAnnotation))
    }

    @Test
    fun `a page already carrying a bookmark reads as bookmarked`() {
        val annotation = Annotation(
            id = "1",
            locator = "3",
            resource = "3",
            progression = 0.3,
            chapter = "",
            text = "Page 4",
            createdAtEpochMillis = 0L,
        )
        assertTrue(ComicPageBookmark.isBookmarked(3, listOf(annotation)))
        assertFalse(ComicPageBookmark.isBookmarked(4, listOf(annotation)))
    }

    @Test
    fun `no bookmarks at all is never bookmarked`() {
        assertFalse(ComicPageBookmark.isBookmarked(0, emptyList()))
    }
}
