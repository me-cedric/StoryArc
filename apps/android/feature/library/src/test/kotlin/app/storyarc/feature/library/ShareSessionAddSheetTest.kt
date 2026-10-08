package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.ShareKey
import app.storyarc.core.model.ShareSessions
import app.storyarc.core.model.ShareTransport
import java.net.InetSocketAddress
import java.net.Socket
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The add sheet records the session it connected with, before any source exists.
 *
 * `close-the-audited-gaps` 23.3: the sheet connects to choose a folder, and the source it saves
 * afterwards is read at once. The detail of that source said no connection had been made,
 * because the sheet's own client recorded nothing. See [ShareSessionRecordTest] for the other
 * paths. Skipped when the fixture server is not running.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShareSessionAddSheetTest {

    private val context: Application get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `the add sheet records, against a share that offers encryption`() = assertSheetRecords(4445)

    @Test
    fun `the add sheet records, against a share that demands encryption`() = assertSheetRecords(4446)

    private fun assertSheetRecords(port: Int) = runBlocking {
        assumeTrue(isRunning(port))
        val key = ShareKey.of("127.0.0.1", port, "COMICS")
        ShareSessions.forget(key)
        val sheet = SmbConnection(context, null)
        sheet.host.value = "127.0.0.1:$port"
        sheet.share.value = "COMICS"
        sheet.username.value = System.getProperty("user.name") ?: "nobody"
        sheet.password.value = "lovelace"

        sheet.connect()
        val step = withTimeout(30_000) {
            sheet.step.first { it is SmbConnection.Step.Browsing || it is SmbConnection.Step.Failed }
        }

        assertTrue("the add sheet did not connect: $step", step is SmbConnection.Step.Browsing)
        assertEquals(ShareTransport("SMB 3.1.1", isEncrypted = true), ShareSessions.all.value[key])
    }

    private fun isRunning(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 300) }
        true
    }.getOrDefault(false)
}
