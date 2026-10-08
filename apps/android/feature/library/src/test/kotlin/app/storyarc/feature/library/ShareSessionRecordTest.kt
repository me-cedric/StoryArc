package app.storyarc.feature.library

import app.storyarc.core.model.ShareKey
import app.storyarc.core.model.ShareSessions
import app.storyarc.core.model.ShareTransport
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbClient
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Every client that connects to a share leaves what its session negotiated, for the source
 * detail screen.
 *
 * `network-share`'s *Encrypted transport*: the screen states whether the connection is
 * encrypted, and it reads [ShareSessions]. It said "No connection has been made" for a share
 * the app had just read, because only the health probe wrote there; the add sheet, the library
 * scan and the reader connected through other clients and recorded nothing
 * (`close-the-audited-gaps` 23.3). Each path is asserted on its own, so a fourth client that
 * skips the record fails by name rather than by silence. The add sheet is
 * [ShareSessionAddSheetTest], which needs a `Context`.
 *
 * Against the two fixture servers, so the value is the one the wire gave:
 * `scripts/smb-server.sh` on 4445 offers encryption, `scripts/smb-server.sh --encrypted` on
 * 4446 demands it. Each test is skipped when its server is not running.
 */
class ShareSessionRecordTest {

    @Test
    fun `the health probe records, against a share that offers encryption`() = assertProbeRecords(4445)

    @Test
    fun `the health probe records, against a share that demands encryption`() = assertProbeRecords(4446)

    @Test
    fun `the library scan records, against a share that offers encryption`() = assertScanRecords(4445)

    @Test
    fun `the library scan records, against a share that demands encryption`() = assertScanRecords(4446)

    @Test
    fun `the reader records, against a share that offers encryption`() = assertReaderRecords(4445)

    @Test
    fun `the reader records, against a share that demands encryption`() = assertReaderRecords(4446)

    @Test
    fun `a saved share's locator finds the session its address recorded`() {
        val address = address(4445)
        ShareSessions.record(key(address), EXPECTED)

        val locator = SmbLocator.of(address.copy(path = "Series/Deep", username = "ada"))

        assertEquals(EXPECTED, ShareSessions.transportOf(locator))
        assertEquals(null, ShareSessions.transportOf("smb://127.0.0.1:1/Comics"))
        assertEquals(null, ShareSessions.transportOf(null))
    }

    private fun assertProbeRecords(port: Int) = runBlocking {
        assumeTrue(isRunning(port))
        val target = address(port)
        ShareSessions.forget(key(target))

        SmbClient(target).use { it.connect() }

        assertEquals(EXPECTED, ShareSessions.all.value[key(target)])
    }

    private fun assertScanRecords(port: Int) = runBlocking {
        assumeTrue(isRunning(port))
        val target = address(port)
        ShareSessions.forget(key(target))

        val page = SmbClient(target).use { SmbContributor.page(UUID.randomUUID(), it, target, listOf("")) }

        assertTrue("the scan read nothing, so it never connected", page.slice.publications.isNotEmpty())
        assertEquals(EXPECTED, ShareSessions.all.value[key(target)])
    }

    private fun assertReaderRecords(port: Int) = runBlocking {
        assumeTrue(isRunning(port))
        val target = address(port)
        ShareSessions.forget(key(target))

        SmbClient(target).use { it.open("Quiet Machines.cbz").close() }

        assertEquals(EXPECTED, ShareSessions.all.value[key(target)])
    }

    private fun address(port: Int) = SmbAddress(
        host = "127.0.0.1",
        share = "Comics",
        username = System.getProperty("user.name") ?: "nobody",
        password = "lovelace",
        port = port,
    )

    private fun key(address: SmbAddress) = ShareKey.of(address.host, address.port, address.share)

    private fun isRunning(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 300) }
        true
    }.getOrDefault(false)

    private companion object {
        val EXPECTED = ShareTransport("SMB 3.1.1", isEncrypted = true)
    }
}
