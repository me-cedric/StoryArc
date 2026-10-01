package app.storyarc.feature.library

import app.storyarc.core.model.Download
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a queue row says about a transfer, beyond the bar.
 *
 * `offline-downloads`: a queued publication is one whose "size is shown, and progress is
 * visible on the publication and in a single downloads view". The bar carried the second
 * half alone. iOS pins the same cases in `DownloadQueueProgressTests.swift`.
 */
class DownloadQueueProgressTest {

    private fun download(
        expected: Long?,
        downloaded: Long,
        state: Download.State = Download.State.Running,
    ) = Download(
        id = "one",
        title = "Harbour Lights 03",
        remote = "https://example.invalid/hl03.epub",
        mediaType = "application/epub+zip",
        state = state,
        expectedBytes = expected,
        downloadedBytes = downloaded,
    )

    @Test
    fun `a sized transfer states both halves and the percentage`() {
        val statement = DownloadQueueProgress.statement(download(expected = 8_400_000, downloaded = 3_100_000))
        assertEquals(DownloadQueueProgress.Statement.Sized(37, 3_100_000, 8_400_000), statement)
    }

    @Test
    fun `an unsized transfer states what has arrived, and no total`() {
        val statement = DownloadQueueProgress.statement(download(expected = null, downloaded = 1_200_000))
        assertEquals(DownloadQueueProgress.Statement.Unsized(1_200_000), statement)
    }

    @Test
    fun `a transfer that has not started still states its size`() {
        val statement = DownloadQueueProgress.statement(
            download(expected = 41_000_000, downloaded = 0, state = Download.State.Queued),
        )
        assertEquals(DownloadQueueProgress.Statement.Sized(0, 0, 41_000_000), statement)
    }

    @Test
    fun `a transfer with no size and no bytes says nothing`() {
        assertNull(DownloadQueueProgress.statement(download(expected = null, downloaded = 0)))
        assertNull(DownloadQueueProgress.statement(download(expected = 0, downloaded = 0)))
    }

    @Test
    fun `a nearly complete transfer never claims to be complete`() {
        val statement = DownloadQueueProgress.statement(download(expected = 10_000_000, downloaded = 9_999_000))
        assertEquals(DownloadQueueProgress.Statement.Sized(99, 9_999_000, 10_000_000), statement)
    }

    @Test
    fun `every byte through is a hundred percent`() {
        val statement = DownloadQueueProgress.statement(download(expected = 10_000_000, downloaded = 10_000_000))
        assertEquals(DownloadQueueProgress.Statement.Sized(100, 10_000_000, 10_000_000), statement)
    }

    @Test
    fun `a failed transfer states no progress`() {
        val statement = DownloadQueueProgress.statement(
            download(
                expected = 2_200_000,
                downloaded = 190_000,
                state = Download.State.Failed(reason = "The server did not answer in time.", attempts = 3),
            ),
        )
        assertNull(statement)
    }

    @Test
    fun `a paused transfer keeps its size`() {
        val statement = DownloadQueueProgress.statement(
            download(
                expected = 8_400_000,
                downloaded = 3_100_000,
                state = Download.State.Paused(Download.Pause.WAITING_FOR_WIFI),
            ),
        )
        assertEquals(DownloadQueueProgress.Statement.Sized(37, 3_100_000, 8_400_000), statement)
    }
}
