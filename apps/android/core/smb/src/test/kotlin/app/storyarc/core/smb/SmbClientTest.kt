package app.storyarc.core.smb

import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Driven against a real SMB2 server rather than a stub.
 *
 * `scripts/smb-server.py` serves the fixture corpus. A stub would prove the code compiles
 * against jcifs' types and nothing about whether the two ends agree, which is the only
 * interesting question a protocol client raises.
 *
 * Skipped when the server is not running, so a checkout without it still builds.
 */
class SmbClientTest {

    /**
     * Authenticated, with signing mandatory on the server.
     *
     * Guest would prove less than nothing: a guest session is unsigned, so it would pass
     * whether or not this client can sign, and signing is what a real share requires.
     */
    private val address = SmbAddress(
        host = "127.0.0.1",
        share = SHARE,
        username = USER,
        password = PASSWORD,
        port = PORT,
    )

    @Test
    fun `connects and says what it negotiated`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            val identity = client.connect()
            assertTrue(identity.dialect.startsWith("SMB "))
            // The server runs with `server signing = mandatory`, so a session that reports
            // itself unsigned here means the client stopped asking -- which is exactly the
            // regression `SmbSigningTest` guards the configuration against, seen from the
            // wire instead of from a property file.
            assertTrue("the session is signed", identity.isSigned)
        }
    }

    @Test
    fun `lists the share, folders before files`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            val entries = client.list("")
            assertTrue(entries.any { it.name == "Quiet Machines.cbz" && !it.isDirectory })
            val firstFile = entries.indexOfFirst { !it.isDirectory }
            val lastFolder = entries.indexOfLast { it.isDirectory }
            if (firstFile >= 0 && lastFolder >= 0) assertTrue(lastFolder < firstFile)
        }
    }

    @Test
    fun `reads part of a file rather than the whole of it`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            client.open("Quiet Machines.cbz").use { source ->
                assertTrue(source.length > 0)
                // A ZIP's End of Central Directory signature lives in the last bytes, and
                // finding it is exactly the ranged read ADR-0008 designed this for.
                val tail = source.read(source.length - 22, 22)
                assertEquals(22, tail.size)

                val head = source.read(0, 4)
                assertEquals("PK".map { it.code.toByte() }, head.take(2))
            }
        }
    }

    /**
     * A share that is not there fails as one of this app's named failures.
     *
     * Not as `ShareNotFound` specifically: impacket drops the connection on an unknown tree
     * connect rather than answering `STATUS_BAD_NETWORK_NAME`, so the branch that reads that
     * status cannot be reached from here. What this does prove is that a jcifs exception
     * never escapes the seam -- which is the part a caller depends on.
     */
    @Test
    fun `a wrong password is rejected, and says so`() {
        assumeTrue(isServerRunning())
        SmbClient(address.copy(password = "wrong")).use { client ->
            assertThrows(SmbError.AuthenticationRejected::class.java) {
                runBlocking { client.connect() }
            }
        }
    }

    @Test
    fun `a malformed host fails as a named error rather than crashing`() {
        SmbClient(address.copy(host = "[fe80")).use { client ->
            assertThrows(SmbError.AddressInvalid::class.java) {
                runBlocking { client.connect() }
            }
        }
    }

    @Test
    fun `a host that refuses the connection is named as unreachable`() {
        // Port 4999 is kept free on purpose (AGENTS.md, the fixture port table): a refused
        // connect is what a host that does not answer looks like. jcifs wraps it in an
        // `SmbException` whose own message names nothing, so only the cause says which.
        SmbClient(address.copy(host = "127.0.0.1", port = REFUSED_PORT)).use { client ->
            assertThrows(SmbError.HostUnreachable::class.java) {
                runBlocking { client.connect() }
            }
        }
    }

    @Test
    fun `a share that is not there fails as a named error, not a raw jcifs one`() {
        assumeTrue(isServerRunning())
        SmbClient(address.copy(share = "NoSuchShare")).use { client ->
            assertThrows(SmbError::class.java) {
                runBlocking { client.connect() }
            }
        }
    }

    /**
     * A read survives the session going away underneath it.
     *
     * `network-share` asks for the session to be re-established "transparently on the next
     * read" after a sleep, and for a drop to be reconnected in the background. Closing the
     * handle out from under the source is the same situation from the source's side: the
     * next read finds a dead handle and has to make another.
     */
    @Test
    fun `a read reopens the session rather than failing`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            val source = client.open("Quiet Machines.cbz")
            val before = source.read(0, 4)

            // What a sleep or a Wi-Fi change leaves behind: a handle that is no longer good.
            source.close()

            val after = source.read(0, 4)
            assertEquals(before.toList(), after.toList())
        }
    }

    /**
     * `network-share`'s *Network changes*: a session `open` handed out is dropped the moment
     * [SmbSourceRegistry.dropAll] runs, which is what [SmbNetworkWatch]'s callback calls on
     * every network-path change. Proved through [SmbSourceRegistry] itself rather than through
     * a fake [android.net.ConnectivityManager] callback, which a JVM unit test has no way to
     * drive — `open` registering every source it hands out is the one thing this test can
     * reach, and it is also the one thing between a network change and any source noticing it.
     *
     * Asserted on [SmbSource.opens] rather than only on the bytes read: a mutation that made
     * [SmbSourceRegistry.dropAll] do nothing would still read the same four bytes off the
     * session that was never closed, which is exactly the false pass a bytes-only assertion
     * would produce here.
     */
    @Test
    fun `a network change drops every open session, not only the one read from`() = runBlocking {
        assumeTrue(isServerRunning())
        SmbClient(address).use { client ->
            val source = client.open("Quiet Machines.cbz") as SmbSource
            val before = source.read(0, 4)
            assertEquals(1, source.opens)

            SmbSourceRegistry.dropAll()

            val after = source.read(0, 4)
            assertEquals(before.toList(), after.toList())
            assertEquals(2, source.opens)
        }
    }

    private companion object {
        const val REFUSED_PORT = 4999
        const val PORT = 4445
        const val SHARE = "Comics"

        /** `smb-server.sh` maps its account onto the machine's own, so the name follows. */
        val USER: String = System.getProperty("user.name") ?: "nobody"
        const val PASSWORD = "lovelace"

        fun isServerRunning(): Boolean = runCatching {
            Socket().use { it.connect(InetSocketAddress("127.0.0.1", PORT), 300) }
            true
        }.getOrDefault(false)
    }
}
