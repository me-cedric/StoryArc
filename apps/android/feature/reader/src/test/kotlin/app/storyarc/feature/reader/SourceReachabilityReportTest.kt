package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.SourceReachabilityEvents
import app.storyarc.core.smb.SmbError
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `network-share`'s *Network changes*, second clause: a read that only fails after the
 * reopened session has also failed means the share is actually gone, and that is the one
 * failure this reports -- not a refused credential, not a damaged archive.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceReachabilityReportTest {

    private fun model(sourceId: UUID? = UUID.randomUUID()) = ReaderViewModel(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = "smb://host/share/a.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "a.cbz",
            origin = MetadataOrigin.INFERRED,
            sourceId = sourceId,
        ),
        resolver = RuntimeEnvironment.getApplication().contentResolver,
        path = "smb://host/share/a.cbz",
    )

    private fun reported(report: () -> Unit): UUID? = runBlocking {
        val received = CompletableDeferred<UUID>()
        val job = launch { SourceReachabilityEvents.unreachable.collect { received.complete(it) } }
        yield()
        report()
        val result = runCatching { withTimeout(300) { received.await() } }.getOrNull()
        job.cancel()
        result
    }

    @Test
    fun `a share that is actually gone is reported, by its source`() {
        val sourceId = UUID.randomUUID()
        val result = reported { model(sourceId).reportIfUnreachable(SmbError.HostUnreachable) }

        assertTrue("Expected $sourceId to be reported.", result == sourceId)
    }

    @Test
    fun `the failure found several layers down the cause chain is still read`() {
        val sourceId = UUID.randomUUID()
        val wrapped = RuntimeException("archive open failed", SmbError.HostUnreachable)
        val result = reported { model(sourceId).reportIfUnreachable(wrapped) }

        assertTrue("A wrapped HostUnreachable must still be found.", result == sourceId)
    }

    @Test
    fun `a publication with no source at all reports nothing`() {
        val result = reported { model(sourceId = null).reportIfUnreachable(SmbError.HostUnreachable) }

        assertFalse("A local publication has no source to report.", result != null)
    }

    @Test
    fun `a refusal that is not the share being gone reports nothing`() {
        val sourceId = UUID.randomUUID()
        val result = reported { model(sourceId).reportIfUnreachable(SmbError.ShareNotFound) }

        assertFalse("ShareNotFound is a refusal, not an unreachable path.", result != null)
    }
}
