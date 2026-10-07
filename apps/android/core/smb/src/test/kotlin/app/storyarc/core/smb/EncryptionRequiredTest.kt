package app.storyarc.core.smb

import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * A server that insists on SMB 3 encryption is reached, encrypted, and says so.
 *
 * jcifs-ng carried the negotiate context for encryption and no cipher, so this test used to
 * assert a refusal. smbj encrypts, so it asserts the connection: the negotiated dialect, the
 * encrypted session, a listing and a ranged read, all through the transform header.
 *
 * `scripts/smb-server.sh --encrypted` serves the fixture corpus with `smb encrypt =
 * required` on port 4446. Skipped when it is not running.
 */
class EncryptionRequiredTest {

    private val address = SmbAddress(
        host = "127.0.0.1",
        share = "Comics",
        username = System.getProperty("user.name") ?: "nobody",
        password = "lovelace",
        port = PORT,
    )

    @Test
    fun `a server that demands encryption gets an encrypted SMB 3 session`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            val identity = client.connect()
            assertTrue("negotiated ${identity.dialect}", identity.dialect.startsWith("SMB 3"))
            assertTrue("the session is not encrypted", identity.isEncrypted)
        }
    }

    @Test
    fun `an encrypted share lists and reads part of a file`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            assertTrue(client.list("").any { it.name == "Quiet Machines.cbz" })
            client.open("Quiet Machines.cbz").use { source ->
                val head = source.read(0, 2)
                assertEquals("PK".map { it.code.toByte() }, head.toList())
            }
        }
    }

    private companion object {
        const val PORT = 4446

        fun isServerRunning(): Boolean = runCatching {
            Socket().use { it.connect(InetSocketAddress("127.0.0.1", PORT), 300) }
            true
        }.getOrDefault(false)
    }
}
