package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `offline-downloads`' *Reading while downloading*, asserted case for case.
 *
 * > **WHEN** a user opens a publication that is still downloading
 * > **THEN** it opens immediately by streaming, and switches to the local copy when the
 * > download completes, without interrupting reading
 *
 * Before this rule existed both platforms waited for the whole file: the publication's page
 * offered a download and nothing else while a transfer of the same book was running.
 *
 * iOS's `ReadingAddressTests` asserts the same cases.
 */
class ReadingAddressTest {

    private fun transfer(
        state: Download.State,
        remote: String = "https://books.example/comic.cbz",
    ) = Download(
        id = "urn:storyarc:6",
        title = "Fine Print",
        remote = remote,
        mediaType = "application/vnd.comicbook+zip",
        state = state,
    )

    @Test
    fun `a running transfer is read from the address it is fetching`() {
        assertEquals(
            "https://books.example/comic.cbz",
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Running),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `a queued transfer is read the same way, before a byte has moved`() {
        // "Opens immediately" is immediate: a reader who presses Read on a publication that
        // is fifth in the queue does not wait for the four ahead of it.
        assertEquals(
            "https://books.example/comic.cbz",
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Queued),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `a transfer held for Wi-Fi is still readable`() {
        // The bytes are on the server whether or not the app is spending mobile data on a
        // copy of them, and a held transfer resumes rather than ends.
        assertEquals(
            "https://books.example/comic.cbz",
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `a copy on the device wins over the transfer that brought it`() {
        assertEquals(
            "/data/downloads/urn-storyarc-6/Fine Print.cbz",
            ReadingAddress.of(
                local = "/data/downloads/urn-storyarc-6/Fine Print.cbz",
                transfer = transfer(Download.State.Running),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `a failed transfer offers no address, so its retry action is what the reader sees`() {
        assertNull(
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Failed("the server refused", 3)),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `a finished transfer with no file left offers no address`() {
        assertNull(
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Finished),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `a decoder that wants a file of its own is never sent an address`() {
        assertNull(
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Running),
                readsWhereItLies = false,
            ),
        )
    }

    @Test
    fun `an address no ranged reader is registered for is never streamed`() {
        // The defect this prevents: a path handed to the opener under a scheme it has no
        // reader for is opened as a local file, and a local file at `ftp://...` is not there.
        assertNull(
            ReadingAddress.of(
                local = null,
                transfer = transfer(Download.State.Running, remote = "ftp://books.example/c.cbz"),
                readsWhereItLies = true,
            ),
        )
    }

    @Test
    fun `no transfer and no copy is nothing to open`() {
        assertNull(ReadingAddress.of(local = null, transfer = null, readsWhereItLies = true))
    }

    @Test
    fun `the copy that arrives for a streamed address is the one fetching it`() {
        val mine = transfer(Download.State.Finished)
        val other = transfer(Download.State.Finished, remote = "https://books.example/other.cbz")
            .copy(id = "urn:storyarc:7")
        val arrived = ReadingAddress.arrived(
            "https://books.example/comic.cbz",
            DownloadLibrary(listOf(other, mine)),
        )
        assertEquals(mine, arrived)
    }

    @Test
    fun `a transfer still running has not arrived`() {
        assertNull(
            ReadingAddress.arrived(
                "https://books.example/comic.cbz",
                DownloadLibrary(listOf(transfer(Download.State.Running))),
            ),
        )
    }

    @Test
    fun `a reader already on a local file has nothing to switch to`() {
        assertNull(
            ReadingAddress.arrived(
                "/data/downloads/urn-storyarc-6/Fine Print.cbz",
                DownloadLibrary(listOf(transfer(Download.State.Finished))),
            ),
        )
    }
}
