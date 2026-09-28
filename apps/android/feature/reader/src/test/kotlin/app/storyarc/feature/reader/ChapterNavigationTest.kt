package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Where the previous or next chapter action goes: within the publication first, and
 * only past its first or last chapter to a neighbouring publication. iOS's
 * `ChapterNavigationTests` asserts the same table.
 */
class ChapterNavigationTest {

    @Test
    fun `the nearest earlier chapter wins, not the first one declared`() {
        assertEquals(30, ChapterNavigation.previousStart(50, listOf(0, 12, 30, 80)))
    }

    @Test
    fun `at or before the first chapter, there is nowhere further back to go`() {
        assertNull(ChapterNavigation.previousStart(12, listOf(12, 30)))
        assertNull(ChapterNavigation.previousStart(5, listOf(12, 30)))
    }

    @Test
    fun `the nearest later chapter wins, not the last one declared`() {
        assertEquals(30, ChapterNavigation.nextStart(20, listOf(0, 12, 30, 80)))
    }

    @Test
    fun `at or past the last chapter, there is nowhere further on to go`() {
        assertNull(ChapterNavigation.nextStart(30, listOf(12, 30)))
        assertNull(ChapterNavigation.nextStart(90, listOf(12, 30)))
    }

    @Test
    fun `no chapter markers at all is nowhere to go, either direction`() {
        assertNull(ChapterNavigation.previousStart(10, emptyList()))
        assertNull(ChapterNavigation.nextStart(10, emptyList()))
    }
}
