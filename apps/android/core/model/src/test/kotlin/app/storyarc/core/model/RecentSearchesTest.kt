package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The recent-search rules, asserted against the same table as iOS's
 * `RecentSearchesTests`.
 *
 * `library-browsing` offers recent queries when search opens, and two independent
 * implementations (ADR-0001) only stay honest if the same cases are put to both.
 * Add a case here, add it there.
 */
class RecentSearchesTest {

    @Test
    fun `the newest search is first`() {
        val searches = RecentSearches().recording("akira").recording("bone")
        assertEquals(listOf("bone", "akira"), searches.terms)
    }

    @Test
    fun `the same search twice is one row, spelled the way it was last typed`() {
        val searches = RecentSearches().recording("Bone").recording("akira").recording("bone")
        assertEquals(listOf("bone", "akira"), searches.terms)
    }

    @Test
    fun `a term that is only whitespace is not a search`() {
        assertTrue(RecentSearches().recording("   ").isEmpty)
    }

    @Test
    fun `the surrounding whitespace is not part of the term`() {
        assertEquals(listOf("bone"), RecentSearches().recording("  bone ").terms)
    }

    @Test
    fun `a word typed one letter at a time is one search, not one per letter`() {
        var searches = RecentSearches()
        for (term in listOf("m", "ma", "man", "mang", "manga")) {
            searches = searches.recording(term)
        }
        assertEquals(listOf("manga"), searches.terms)
    }

    @Test
    fun `deleting a term back to nothing does not file the letters on the way out`() {
        val searches = RecentSearches().recording("manga").recording("mang").recording("m")
        assertEquals(listOf("manga"), searches.terms)
    }

    @Test
    fun `an older term that happens to be a prefix is left where it is`() {
        // "m" is a search of its own here: another search happened after it, so the
        // reader deliberately came back to it rather than passing through it.
        val searches = RecentSearches().recording("m").recording("bone").recording("manga")
        assertEquals(listOf("manga", "bone", "m"), searches.terms)
    }

    @Test
    fun `the list stops at its limit, and the oldest is what falls off`() {
        var searches = RecentSearches()
        for (index in 1..RecentSearches.LIMIT + 1) {
            searches = searches.recording("term $index")
        }
        assertEquals(RecentSearches.LIMIT, searches.terms.size)
        assertEquals("term ${RecentSearches.LIMIT + 1}", searches.terms.first())
        assertFalse(searches.terms.contains("term 1"))
    }
}
