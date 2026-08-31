package app.storyarc.core.persistence

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a stored language tag means.
 *
 * The one decision inside `speaking()`, pulled out so it can be asserted without a device.
 * The rest of that function is two platform calls with nothing to get wrong; this is the
 * part that can silently put the interface in a language nobody chose.
 */
class InterfaceLanguageTest {

    @Test
    fun `no choice leaves the system language alone`() {
        assertNull(interfaceLocale(null))
    }

    @Test
    fun `a blank tag is no choice, not the root locale`() {
        // `Locale.forLanguageTag("")` answers ROOT rather than refusing, and a root-locale
        // interface is a thing no reader ever asked for. Blank has to mean the same as null.
        assertNull(interfaceLocale(""))
        assertNull(interfaceLocale("   "))
    }

    @Test
    fun `a tag nothing can parse is no choice either`() {
        // Same trap, one step along: `forLanguageTag` answers ROOT for anything malformed
        // rather than refusing, so guarding the input against blankness caught one case out
        // of many. The guard is on the answer, which catches all of them.
        listOf("!!", "??-??", "1234", "a".repeat(64)).forEach { tag ->
            assertNull(tag, interfaceLocale(tag))
        }
    }

    @Test
    fun `the four shipped languages resolve to themselves`() {
        // The four `localization` requires. A tag that resolved to something else here would
        // put the whole interface, both activities, in the wrong language.
        listOf("en", "fr", "de", "es").forEach { tag ->
            assertEquals(tag, interfaceLocale(tag)?.language)
        }
    }

    @Test
    fun `a region keeps its region`() {
        val locale = interfaceLocale("pt-BR")

        assertEquals("pt", locale?.language)
        assertEquals("BR", locale?.country)
    }

    @Test
    fun `a tag is read as a tag rather than as a locale name`() {
        // `Locale.forLanguageTag` and the deprecated `Locale(String)` disagree about
        // underscores, and the settings screen stores BCP-47.
        assertEquals(Locale.forLanguageTag("fr"), interfaceLocale("fr"))
    }
}
