package app.storyarc.core.smb

import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * A server that insists on SMB 3 encryption is refused, and named.
 *
 * jcifs-ng carries the negotiate context for encryption but no cipher to go with it: asked
 * to talk to such a server it answers "Server requires encryption, not yet supported". That
 * is a real limit of the client, and the app turns it into a sentence a reader can act on
 * rather than a fifth way of saying "could not connect".
 *
 * `scripts/smb-server.sh --encrypted` serves the fixture corpus with `smb encrypt =
 * required`. Skipped when it is not running.
 */
class EncryptionRequiredTest {
    @Test
    fun `a server that demands encryption is named as such`() {
        assumeTrue(isServerRunning())
        val address = SmbAddress(
            host = "127.0.0.1",
            share = "Comics",
            username = System.getProperty("user.name") ?: "nobody",
            password = "lovelace",
            port = PORT,
        )
        val thrown = runCatching { runBlocking { SmbClient(address).use { it.connect() } } }
            .exceptionOrNull()
        assertEquals(SmbError.EncryptionRequired, thrown)
    }

    private companion object {
        const val PORT = 4446

        fun isServerRunning(): Boolean = runCatching {
            Socket().use { it.connect(InetSocketAddress("127.0.0.1", PORT), 300) }
            true
        }.getOrDefault(false)
    }
}
