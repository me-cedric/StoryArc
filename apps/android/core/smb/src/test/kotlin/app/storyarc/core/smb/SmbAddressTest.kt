package app.storyarc.core.smb

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmbAddressTest {

    @Test
    fun `reads an smb url`() {
        val address = SmbAddress.parse("smb://nas.local/Comics/Manga")
        assertEquals("nas.local", address?.host)
        assertEquals("Comics", address?.share)
        assertEquals("Manga", address?.path)
    }

    @Test
    fun `reads the windows form, which is what a reader has to hand`() {
        val address = SmbAddress.parse("""\\nas.local\Comics\Manga\Ongoing""")
        assertEquals("nas.local", address?.host)
        assertEquals("Comics", address?.share)
        assertEquals("Manga/Ongoing", address?.path)
    }

    @Test
    fun `keeps a port when one is given`() {
        assertEquals(4445, SmbAddress.parse("smb://localhost:4445/Comics")?.port)
    }

    @Test
    fun `refuses a host with no share, which names nothing to read`() {
        assertNull(SmbAddress.parse("smb://nas.local"))
        assertNull(SmbAddress.parse(""))
    }

    @Test
    fun `builds a url that jcifs accepts`() {
        val address = SmbAddress(host = "nas", share = "Comics", path = "Manga")
        assertEquals("smb://nas/Comics/Manga/", address.url())
        assertEquals("smb://nas/Comics/", address.url(""))
    }

    @Test
    fun `keeps a non-standard port in the url`() {
        val address = SmbAddress(host = "localhost", share = "Comics", port = 4445)
        assertEquals("smb://localhost:4445/Comics/", address.url())
    }

    @Test
    fun `a nameless connection is a guest one`() {
        assertTrue(SmbAddress(host = "nas", share = "Comics").isGuest)
        assertFalse(SmbAddress(host = "nas", share = "Comics", username = "ada").isGuest)
    }
}
