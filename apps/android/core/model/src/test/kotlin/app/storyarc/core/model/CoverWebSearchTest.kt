package app.storyarc.core.model

import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The address the system browser is handed, and what it does not carry.
 *
 * iOS's `CoverWebSearchTests` makes the same claims about the same address.
 */
class CoverWebSearchTest {

    @Test
    fun `the search is for the title, the author and the word cover`() {
        val url = CoverWebSearch.url("Fine Print", "Ada Lovelace")
        assertTrue(url!!.contains("q=Fine+Print+Ada+Lovelace+cover"))
    }

    @Test
    fun `a title with no author still searches`() {
        assertTrue(CoverWebSearch.url("Book 03")!!.contains("q=Book+03+cover"))
    }

    @Test
    fun `an empty title opens nothing`() {
        // A search for nothing lands on an engine's front page, and handing a reader that is
        // worse than not offering the action at all.
        assertNull(CoverWebSearch.url("   "))
    }

    @Test
    fun `the hand-off goes to an engine that keeps no profile`() {
        // The app has no analytics and no account. Choosing an engine that builds a profile
        // against a signed-in identity would undo that at the one moment the app picks the
        // address.
        assertTrue(CoverWebSearch.url("Fine Print")!!.startsWith("https://duckduckgo.com/"))
    }

    @Test
    fun `the image results are what opens`() {
        val url = CoverWebSearch.url("Fine Print")!!
        assertTrue(url.contains("iax=images"))
        assertTrue(url.contains("ia=images"))
    }
}
