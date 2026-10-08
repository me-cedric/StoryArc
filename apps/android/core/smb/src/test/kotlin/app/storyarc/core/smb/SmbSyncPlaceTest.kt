package app.storyarc.core.smb

import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * `library-sync` task 2.2: the sync document written to a share, against a real Samba.
 *
 * `scripts/smb-server.sh --writable` serves a writable `Sync` share on 4448, signed.
 * `scripts/smb-server.sh --writable --encrypted` serves the same on 4449 with
 * `smb encrypt = required`. Each case is skipped when its server is not running.
 */
class SmbSyncPlaceTest {

    @Test
    fun `a signed share takes a write, gives it back, and takes an overwrite at that version`() =
        writesReadsAndOverwrites(SIGNED_PORT)

    @Test
    fun `an encrypted share takes a write, gives it back, and takes an overwrite at that version`() =
        writesReadsAndOverwrites(ENCRYPTED_PORT)

    @Test
    fun `a write against a version that changed writes nothing`() = runBlocking {
        assumeTrue(isServerRunning(SIGNED_PORT))
        SmbSyncPlace(address(SIGNED_PORT)).use { place ->
            val name = fileName()
            assertTrue(place.write(name, "first", replacing = null))
            // Absent was expected, and the file is there.
            assertFalse(place.write(name, "second", replacing = null))
            assertFalse(place.write(name, "second", replacing = "not-the-version"))
            assertEquals("first", place.read(name)?.text)
            assertTrue(place.delete(name))
        }
    }

    @Test
    fun `a deleted file is gone and reads as none`() = runBlocking {
        assumeTrue(isServerRunning(SIGNED_PORT))
        SmbSyncPlace(address(SIGNED_PORT)).use { place ->
            val name = fileName()
            assertTrue(place.write(name, "doomed", replacing = null))
            assertTrue(name in place.names())
            assertTrue(place.delete(name))
            assertNull(place.read(name))
            assertFalse(name in place.names())
            // No temporary file is left beside the document.
            assertTrue(place.names().none { it.endsWith(".tmp") })
        }
    }

    @Test
    fun `a share that does not answer is unreachable, not an error`() {
        val place = SmbSyncPlace(address(REFUSED_PORT))
        assertThrows(SmbError.HostUnreachable::class.java) {
            runBlocking { place.read("StoryArc Library.json") }
        }
        assertThrows(SmbError.HostUnreachable::class.java) {
            runBlocking { place.write("StoryArc Library.json", "{}", null) }
        }
    }

    private fun writesReadsAndOverwrites(port: Int) = runBlocking {
        assumeTrue(isServerRunning(port))
        SmbSyncPlace(address(port)).use { place ->
            val name = fileName()
            assertNull(place.read(name))
            assertTrue(place.write(name, "one", replacing = null))
            val first = place.read(name)!!
            assertEquals("one", first.text)

            assertTrue(place.write(name, "two, longer", replacing = first.version))
            val second = place.read(name)!!
            assertEquals("two, longer", second.text)
            assertNotEquals(first.version, second.version)
            assertTrue(place.delete(name))
        }
    }

    private companion object {
        const val SIGNED_PORT = 4448
        const val ENCRYPTED_PORT = 4449
        const val REFUSED_PORT = 4999
        val USER: String = System.getProperty("user.name") ?: "nobody"

        fun address(port: Int) = SmbAddress(
            host = "127.0.0.1",
            share = "Sync",
            username = USER,
            password = "lovelace",
            port = port,
        )

        /** A name of its own per case, so cases on one share never see each other's file. */
        fun fileName() = "StoryArc Library ${UUID.randomUUID()}.json"

        fun isServerRunning(port: Int): Boolean = runCatching {
            Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 300) }
            true
        }.getOrDefault(false)
    }
}
