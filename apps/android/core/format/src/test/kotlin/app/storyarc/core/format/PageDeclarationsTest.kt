package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Bounding a container's declared indices against the page list it actually has. iOS's
 * `PageDeclarationsTests` asserts the same table.
 */
class PageDeclarationsTest {
    private val pages = (0 until 5).map { PageEntry(path = "$it.jpg") }

    @Test
    fun `every in-range chapter start is kept`() {
        assertEquals(listOf(0, 2, 4), PageDeclarations.chapterStarts(pages, listOf(0, 2, 4)))
    }

    @Test
    fun `a chapter start past the page list is dropped, not clamped to the last page`() {
        assertEquals(listOf(2), PageDeclarations.chapterStarts(pages, listOf(2, 9)))
    }

    @Test
    fun `a negative chapter start is dropped`() {
        assertEquals(listOf(3), PageDeclarations.chapterStarts(pages, listOf(-1, 3)))
    }

    @Test
    fun `no declared chapters at all is no chapters`() {
        assertTrue(PageDeclarations.chapterStarts(pages, emptyList()).isEmpty())
    }
}
