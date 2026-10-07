package app.storyarc.feature.library

import app.storyarc.core.model.ShareSessions
import app.storyarc.core.model.ShareTransport
import app.storyarc.core.smb.SmbAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * A probe of a share keeps what its session negotiated, for the source detail screen.
 *
 * `network-share`'s *Encrypted transport*: the screen states whether the connection is
 * encrypted. It reads [ShareSessions], and the probe is what writes there. Against the two
 * fixture servers, so the value is the one the wire gave: `scripts/smb-server.sh` on 4445
 * offers encryption, `scripts/smb-server.sh --encrypted` on 4446 demands it. Each test is
 * skipped when its server is not running.
 */
class ShareSessionRecordTest {

    @Test
    fun `a probe of a share that offers encryption keeps an encrypted SMB 3 session`() =
        assertKept(port = 4445)

    @Test
    fun `a probe of a share that demands encryption keeps an encrypted SMB 3 session`() =
        assertKept(port = 4446)

    private fun assertKept(port: Int) = runBlocking {
        assumeTrue(isRunning(port))
        val source = UUID.randomUUID()

        SourceHealth.reachShare(source, address(port))

        assertEquals(ShareTransport("SMB 3.1.1", isEncrypted = true), ShareSessions.all.value[source])
    }

    private fun address(port: Int) = SmbAddress(
        host = "127.0.0.1",
        share = "Comics",
        username = System.getProperty("user.name") ?: "nobody",
        password = "lovelace",
        port = port,
    )

    private fun isRunning(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 300) }
        true
    }.getOrDefault(false)
}
