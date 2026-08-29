package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors iOS's `ExcerptTests`, assertion for assertion. */
class ExcerptTest {

    private val prose =
        "Alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima " +
            "mike november oscar papa quebec romeo sierra tango uniform victor whisky."

    @Test
    fun `an excerpt starts at a word, not in the middle of one`() {
        val text = Excerpt.at(prose, fraction = 0.5, length = 40)
        assertTrue("started mid-word: $text", prose.contains(" $text") || prose.startsWith(text))
    }

    @Test
    fun `an excerpt ends at a word when there was more to come`() {
        val text = Excerpt.at(prose, fraction = 0.0, length = 40)
        assertFalse(text.endsWith(" "))
        assertTrue(prose.startsWith(text))
        assertTrue(text.length <= 40)
    }

    @Test
    fun `the end of the text is not trimmed away looking for a space`() {
        val text = Excerpt.at(prose, fraction = 0.99, length = 400)
        assertTrue("lost the tail: $text", text.endsWith("whisky."))
    }

    @Test
    fun `a fraction outside the text is pulled back into it`() {
        assertEquals(Excerpt.at(prose, fraction = 1.0), Excerpt.at(prose, fraction = 4.2))
        assertEquals(Excerpt.at(prose, fraction = 0.0), Excerpt.at(prose, fraction = -1.0))
    }

    @Test
    fun `nothing to quote gives nothing, rather than whitespace`() {
        assertEquals("", Excerpt.at("", fraction = 0.5))
        assertEquals("", Excerpt.at("   \n  ", fraction = 0.5))
    }

    @Test
    fun `markup is not part of the text`() {
        val markup = "<p class=\"x\">Alpha <em>bravo</em> charlie.</p>"
        assertEquals("Alpha bravo charlie.", Excerpt.plainText(markup))
    }

    @Test
    fun `a script is not text, whatever a tag stripper thinks`() {
        val markup = "<p>Alpha</p><script>var hidden = 'bravo';</script><p>charlie</p>"
        val text = Excerpt.plainText(markup)
        assertFalse("script leaked: $text", text.contains("hidden"))
        assertEquals("Alpha charlie", text)
    }

    @Test
    fun `the head is not text a reader ever saw`() {
        val markup =
            "<html><head><title>Chapter Two</title></head><body><p>Alpha bravo.</p></body></html>"
        assertEquals("Alpha bravo.", Excerpt.plainText(markup))
    }

    @Test
    fun `the entities a book actually uses come back as characters`() {
        assertEquals("Salt & pepper", Excerpt.plainText("<p>Salt &amp; pepper</p>"))
        assertEquals("a b", Excerpt.plainText("<p>a&nbsp;b</p>"))
    }
}
