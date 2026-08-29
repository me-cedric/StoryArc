package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors iOS's `SearchSnippetTests`, assertion for assertion. */
class SearchSnippetTest {

    private val long = "word ".repeat(60)

    @Test
    fun `the match survives whatever the budget is`() {
        val snippet = SearchSnippet.of(long, "sandman", long, budget = 10)
        assertEquals("sandman", snippet.match)
        assertTrue(snippet.line.contains("sandman"))
    }

    @Test
    fun `a match longer than the whole budget is still not cut`() {
        val match = "x".repeat(200)
        assertEquals(match, SearchSnippet.of("a", match, "b", budget = 10).match)
    }

    @Test
    fun `context is trimmed to the budget when both sides are long`() {
        val snippet = SearchSnippet.of(long, "m", long, budget = 40)
        assertTrue(snippet.before.length <= 20)
        assertTrue(snippet.after.length <= 20)
    }

    @Test
    fun `what one side does not use, the other may`() {
        val snippet = SearchSnippet.of("", "m", long, budget = 40)
        assertTrue(snippet.before.isEmpty())
        assertTrue(snippet.after.length > 20)
    }

    @Test
    fun `leading context keeps the words nearest the match, not the first ones`() {
        val snippet = SearchSnippet.of("alpha bravo charlie delta echo foxtrot", "m", "", budget = 20)
        assertTrue(snippet.before.endsWith("foxtrot"))
        assertFalse(snippet.before.contains("alpha"))
    }

    @Test
    fun `trailing context keeps the words nearest the match`() {
        val snippet = SearchSnippet.of("", "m", "alpha bravo charlie delta echo foxtrot", budget = 20)
        assertTrue(snippet.after.startsWith("alpha"))
        assertFalse(snippet.after.contains("foxtrot"))
    }

    @Test
    fun `a short context is left alone`() {
        val snippet = SearchSnippet.of("a short lead", "m", "a short tail")
        assertEquals("a short lead", snippet.before)
        assertEquals("a short tail", snippet.after)
    }

    @Test
    fun `the line reads as one sentence, with no gaps where a side was empty`() {
        assertEquals("m", SearchSnippet.of("", "m", "").line)
        assertEquals("a m", SearchSnippet.of("a", "m", "").line)
        assertEquals("m b", SearchSnippet.of("", "m", "b").line)
    }

    @Test
    fun `whitespace the renderer left on the context does not reach the row`() {
        val snippet = SearchSnippet.of("  lead \n", "m", "\n tail  ")
        assertEquals("lead", snippet.before)
        assertEquals("tail", snippet.after)
    }
}
