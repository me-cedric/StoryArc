package app.storyarc.core.smb

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The server picks the name. iOS's `SmbEntryNameTests` asserts the same cases in the same
 * order.
 */
class SmbEntryNameTest {
    private val directory = File(System.getProperty("java.io.tmpdir"), "smb")

    private fun entry(name: String) = SmbEntry(name, name, isDirectory = false, length = 1L)

    @Test
    fun `a name full of dot segments is written under the cache, not above it`() {
        // The name a hostile server serves to reach the app's own preferences. The
        // decoders that need a real file are the ones that make the app write it down.
        val local = entry("../shared_prefs/settings.xml").cacheLocation(directory)

        assertNotNull(local)
        assertEquals("settings.xml", local?.name)
        assertTrue(
            "wrote outside the cache directory: ${local?.canonicalPath}",
            local?.canonicalPath?.startsWith(directory.canonicalPath + File.separator) == true,
        )
    }

    @Test
    fun `a windows separator is a separator too, and only the last component survives`() {
        // SMB's own separator. A rule that only knows about `/` is a rule the protocol
        // was never written in.
        val local = entry("""..\..\shared_prefs\settings.xml""").cacheLocation(directory)

        assertEquals("settings.xml", local?.name)
        assertTrue(
            local?.canonicalPath?.startsWith(directory.canonicalPath + File.separator) == true,
        )
    }

    @Test
    fun `a name that is nothing but dots has no last component worth keeping`() {
        // Refused outright rather than trimmed, the same way a download id is: trimming
        // is what invites `....//` and the rest of that family.
        for (name in listOf(".", "..", "...", "../..", "./.")) {
            assertNull("`$name` was accepted", entry(name).cacheLocation(directory))
        }
    }

    @Test
    fun `an empty or separator-only name is refused`() {
        for (name in listOf("", "/", """\""", "//")) {
            assertNull("`$name` was accepted", entry(name).cacheLocation(directory))
        }
    }

    @Test
    fun `an ordinary name is left exactly as the server sent it`() {
        val local = entry("Saga 001 (2012).cbz").cacheLocation(directory)
        assertEquals("Saga 001 (2012).cbz", local?.name)
    }
}
