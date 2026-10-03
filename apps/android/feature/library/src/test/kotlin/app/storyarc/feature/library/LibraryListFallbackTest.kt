package app.storyarc.feature.library

import app.storyarc.core.model.LibraryLayout
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Task 19.6: the library "does not fall back to a list at accessibility text sizes" — the
 * grid stayed a grid, however wide its captions had wrapped. [libraryFallsBackToList] is
 * the whole rule, asked without composing a shelf. iOS asserts the same answer in
 * `LibraryListFallbackTests.swift`, because Swift Testing lets it compute what Android would
 * otherwise need Robolectric to draw.
 */
class LibraryListFallbackTest {

    @Test
    fun `grid stays grid at an ordinary font scale`() {
        assertFalse(libraryFallsBackToList(LibraryLayout.GRID, fontScale = 1.0f))
    }

    @Test
    fun `grid still falls back to list right at the accessibility step`() {
        assertTrue(libraryFallsBackToList(LibraryLayout.GRID, fontScale = 1.3f))
    }

    @Test
    fun `grid still falls back to list well past the accessibility step`() {
        assertTrue(libraryFallsBackToList(LibraryLayout.GRID, fontScale = 2.0f))
    }

    @Test
    fun `list stays list at an ordinary font scale -- nothing changes underneath the reader`() {
        assertTrue(libraryFallsBackToList(LibraryLayout.LIST, fontScale = 1.0f))
    }

    @Test
    fun `the largest ordinary font scale does not fall back`() {
        assertFalse(libraryFallsBackToList(LibraryLayout.GRID, fontScale = 1.29f))
    }
}
