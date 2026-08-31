package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `offline-downloads`: "its integrity is verified before it is marked available offline, and
 * a failed verification re-queues it once". iOS's `DownloadVerificationTests` asserts the
 * same cases.
 *
 * "Once" is the whole rule and the only number in it, so every case here is about the
 * boundary: the first corrupt arrival is re-fetched, the second is not, and the count it
 * keeps is not the one the network failures use.
 */
class DownloadVerificationTest {
    private val unreadable = "the file could not be read"

    private fun download(
        id: String = "urn:one",
        verificationFailures: Int = 0,
        state: Download.State = Download.State.Running,
    ) = Download(
        id = id,
        title = id,
        remote = "https://example.test/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
        verificationFailures = verificationFailures,
    )

    private fun library(download: Download) = DownloadLibrary(listOf(download))

    @Test
    fun `the first corrupt arrival goes back in the queue`() {
        val after = library(download()).failingVerification("urn:one", unreadable)

        assertEquals(Download.State.Queued, after["urn:one"]?.state)
        assertEquals(1, after["urn:one"]?.verificationFailures)
    }

    @Test
    fun `the second corrupt arrival is failed with the reason`() {
        val after = library(download())
            .failingVerification("urn:one", unreadable)
            .failingVerification("urn:one", unreadable)

        assertEquals(
            Download.State.Failed(unreadable, DownloadLibrary.ATTEMPT_LIMIT),
            after["urn:one"]?.state,
        )
        assertEquals(2, after["urn:one"]?.verificationFailures)
    }

    @Test
    fun `a third is not asked for either`() {
        var after = library(download())
        repeat(3) { after = after.failingVerification("urn:one", unreadable) }

        assertEquals(
            Download.State.Failed(unreadable, DownloadLibrary.ATTEMPT_LIMIT),
            after["urn:one"]?.state,
        )
    }

    @Test
    fun `the re-queue is asked for before it is spent, and refused after`() {
        assertTrue(DownloadLibrary.shouldRequeueAfterVerification(download()))
        assertFalse(
            DownloadLibrary.shouldRequeueAfterVerification(download(verificationFailures = 1)),
        )
        assertFalse(
            DownloadLibrary.shouldRequeueAfterVerification(download(verificationFailures = 2)),
        )
    }

    @Test
    fun `a verification failure does not spend a transfer attempt`() {
        // Three failed transfers and one corrupt arrival are four different events. Sharing a
        // counter would let a flaky network burn the verification's only second chance before
        // the bytes ever landed, or let three corrupt files be re-fetched.
        val flaky = library(download())
            .failing("urn:one", "the server did not answer")
            .failing("urn:one", "the server did not answer")

        val corrupt = flaky.failingVerification("urn:one", unreadable)

        assertEquals(Download.State.Queued, corrupt["urn:one"]?.state)
        assertEquals(1, corrupt["urn:one"]?.verificationFailures)
        // And the other way: the transfer count is untouched by the corrupt arrival, so a
        // download that goes back to the network still has the attempt it had left.
        assertTrue(DownloadLibrary.shouldRetry(requireNotNull(flaky["urn:one"])))
    }

    @Test
    fun `only the named download is touched`() {
        val both = DownloadLibrary(
            listOf(download(), download(id = "urn:two", state = Download.State.Queued)),
        )

        val after = both.failingVerification("urn:one", unreadable)

        assertEquals(0, after["urn:two"]?.verificationFailures)
        assertEquals(Download.State.Queued, after["urn:two"]?.state)
    }

    @Test
    fun `one, from the spec's own word`() {
        assertEquals(1, DownloadLibrary.VERIFICATION_LIMIT)
    }
}
