package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The key a connection and a saved source's locator must agree on, or the detail screen reads
 * an answer nobody wrote (`close-the-audited-gaps` 23.3). iOS's `ShareKeyTests` is the mirror.
 */
class ShareKeyTest {

    private val nas = ShareKey.of("nas.local", 445, "Comics")

    @Test
    fun `a locator names the same share as the address it was written from`() {
        assertEquals(nas, ShareKey.ofLocator("smb://nas.local/Comics"))
        assertEquals(nas, ShareKey.ofLocator("smb://ada@nas.local/Comics/Series/Deep"))
        assertEquals(nas, ShareKey.ofLocator("smb://nas.local:445/Comics"))
    }

    @Test
    fun `the port is part of the share`() {
        assertEquals(ShareKey.of("nas.local", 4446, "Comics"), ShareKey.ofLocator("smb://nas.local:4446/Comics"))
        assertNotEquals(nas, ShareKey.ofLocator("smb://nas.local:4446/Comics"))
    }

    @Test
    fun `host and share compare without regard to case, and folders below the share do not count`() {
        assertEquals(nas, ShareKey.ofLocator("smb://NAS.local/COMICS/a/b"))
        assertNotEquals(nas, ShareKey.ofLocator("smb://nas.local/Other"))
    }

    @Test
    fun `text that is not a share locator has no key`() {
        for (text in listOf("", "https://nas.local/Comics", "smb://", "smb://nas.local", "smb://nas.local:port/Comics")) {
            assertNull(text, ShareKey.ofLocator(text))
        }
    }
}
