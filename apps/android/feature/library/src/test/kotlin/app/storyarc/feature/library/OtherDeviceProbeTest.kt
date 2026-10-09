package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketTimeoutException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `library-sync` task 5.8: a loopback address that a sync brought from another device names that
 * device, so nothing here tries it. A listening socket on this host proves that no connection
 * comes. The same address added on this device is tried.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OtherDeviceProbeTest {

    private fun share(port: Int, fromAnotherDevice: Boolean) = Source(
        displayName = "Simulator share",
        kind = SourceKind.NETWORK_SHARE,
        locator = "smb://127.0.0.1:$port/Sync",
        fromAnotherDevice = fromAnotherDevice,
    )

    /** Whether anything connected to [server] within half a second. */
    private fun connected(server: ServerSocket): Boolean = try {
        server.soTimeout = 500
        server.accept().close()
        true
    } catch (_: SocketTimeoutException) {
        false
    }

    @Test
    fun `a loopback share from another device is not tried, and reads as not answering`() = runTest {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
            val source = share(server.localPort, fromAnotherDevice = true)

            val state = SourceHealth.probe(source, null, CertificatePins(), 42, "refused", "encrypted")

            assertEquals(SourceConnectionState.Unreachable(42), state)
            assertNull(SmbPage.of(source, null))
            assertNull(KavitaPage.of(source.copy(kind = SourceKind.KAVITA_SERVER, locator = "http://127.0.0.1:5000"), null))
            assertNull(CataloguePage.of(source.copy(kind = SourceKind.OPDS_CATALOG, locator = "http://localhost/opds"), null))
            assertTrue(!connected(server))
        }
    }

    @Test
    fun `the same share added on this device is tried`() {
        ServerSocket(0, 1, InetAddress.getLoopbackAddress()).use { server ->
            assertNotNull(SmbPage.of(share(server.localPort, fromAnotherDevice = false), null))
        }
    }
}
