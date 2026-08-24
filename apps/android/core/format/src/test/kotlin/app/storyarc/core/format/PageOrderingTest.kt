package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure ordering logic. iOS's `PageOrderingTests` asserts the same cases — this
 * is the layer most likely to drift between two implementations, so it is the
 * layer held to the same table on both.
 */
class PageOrderingTest {
    private fun order(vararg paths: String) = PageOrdering.pages(paths.toList()).map { it.path }

    @Test
    fun `page10 sorts after page9, not after page1`() {
        assertEquals(
            listOf("page1.png", "page2.png", "page9.png", "page10.png", "page11.png"),
            order("page1.png", "page10.png", "page2.png", "page9.png", "page11.png"),
        )
    }

    @Test
    fun `chapter directories order naturally by full path`() {
        assertEquals(
            listOf("ch1/p1.png", "ch1/p2.png", "ch1/p10.png", "ch2/p1.png", "ch10/p1.png"),
            order("ch10/p1.png", "ch2/p1.png", "ch1/p10.png", "ch1/p2.png", "ch1/p1.png"),
        )
    }

    @Test
    fun `leading zeros do not change the value but keep the order total`() {
        // 7 == 7, so the shorter run wins the tie. What matters is that the order
        // is deterministic and 8 still comes last.
        assertEquals(listOf("p7.png", "p007.png", "p8.png"), order("p007.png", "p7.png", "p8.png"))
    }

    @Test
    fun `a digit sorts before a letter`() {
        assertTrue(PageOrdering.naturalCompare("p1.png", "pa.png") < 0)
        assertTrue(PageOrdering.naturalCompare("pa.png", "p1.png") > 0)
    }

    @Test
    fun `ordering is case-insensitive but not locale-dependent`() {
        assertEquals(listOf("a.png", "B.png", "C.png"), order("B.png", "a.png", "C.png"))
    }

    @Test
    fun `very large page numbers do not overflow into a wrong order`() {
        assertEquals(listOf("p2.png", "p99999999999.png"), order("p99999999999.png", "p2.png"))
    }

    @Test
    fun `a digit run longer than any integer type still orders correctly`() {
        // The reason both platforms compare digits rather than parsing them: a
        // 40-digit run has no integer representation on either side.
        val long = "p" + "9".repeat(40) + ".png"
        val longer = "p1" + "0".repeat(40) + ".png"
        assertEquals(listOf(long, longer), order(longer, long))
    }

    @Test
    fun `ComicInfo xml is never a page`() {
        assertFalse(PageOrdering.isPage("ComicInfo.xml"))
        assertFalse(PageOrdering.isPage("comicinfo.xml"))
    }

    @Test
    fun `macOS resource forks are excluded, or every page would be counted twice`() {
        assertFalse(PageOrdering.isPage("__MACOSX/._page1.png"))
        assertFalse(PageOrdering.isPage("._page1.png"))
    }

    @Test
    fun `OS cruft is excluded`() {
        assertFalse(PageOrdering.isPage("Thumbs.db"))
        assertFalse(PageOrdering.isPage(".DS_Store"))
        assertFalse(PageOrdering.isPage("notes.txt"))
    }

    @Test
    fun `directory entries are not pages`() {
        assertFalse(PageOrdering.isPage("chapter1/"))
    }

    @Test
    fun `every supported image codec is accepted, in any case`() {
        for (ext in listOf("jpg", "JPEG", "png", "WebP", "avif", "gif", "heic", "heif", "bmp", "tiff")) {
            assertTrue("rejected .$ext", PageOrdering.isPage("page.$ext"))
        }
    }
}
