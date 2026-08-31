package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `offline-downloads`' *Reading while downloading*, as far as the queue's order can carry it.
 * iOS's `DownloadPromotionTests` asserts the same cases.
 *
 * The scenario asks for a publication that is still downloading to open immediately and to
 * hand over to the local copy when it lands. The hand-over half already holds -- a reader who
 * taps *Read* is given the file the moment it lands, and reading is not interrupted because
 * it has not started. What this fixes is the wait before it: the download a reader is waiting
 * on used to go to the **back** of the queue, so on a metered link, where the concurrency
 * bound is one, they waited out everything they had lined up earlier and were not reading.
 *
 * What is still missing is streaming itself, and it is missing outside this file: no
 * `RandomAccessSource` over HTTP range requests is registered, so a publication that is still
 * arriving cannot be read from the server while it arrives.
 */
class DownloadPromotionTest {
    private fun download(id: String, state: Download.State = Download.State.Queued) = Download(
        id = id,
        title = id,
        remote = "https://example.test/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
    )

    private fun ids(library: DownloadLibrary) = library.downloads.map { it.id }

    @Test
    fun `the waited-on download moves ahead of what was queued before it`() {
        val library = DownloadLibrary(
            listOf(download("big"), download("other"), download("wanted")),
        )

        assertEquals(listOf("wanted", "big", "other"), ids(library.promoting("wanted")))
    }

    @Test
    fun `a running download keeps its slot`() {
        // Nothing is cancelled and nothing is preempted: this is the reorder the spec already
        // grants the reader, not a priority scheme.
        val library = DownloadLibrary(
            listOf(
                download("running", Download.State.Running),
                download("big"),
                download("wanted"),
            ),
        )

        assertEquals(listOf("running", "wanted", "big"), ids(library.promoting("wanted")))
    }

    @Test
    fun `a download already at the head is left where it is`() {
        val library = DownloadLibrary(listOf(download("wanted"), download("big")))

        assertEquals(library, library.promoting("wanted"))
    }

    @Test
    fun `only a queued download can be promoted`() {
        val library = DownloadLibrary(
            listOf(
                download("big"),
                download("running", Download.State.Running),
                download("done", Download.State.Finished),
                download("held", Download.State.Paused(Download.Pause.BY_READER)),
            ),
        )

        assertEquals(library, library.promoting("running"))
        assertEquals(library, library.promoting("done"))
        assertEquals(library, library.promoting("held"))
        assertEquals(library, library.promoting("absent"))
    }

    @Test
    fun `everything else keeps its order`() {
        val library = DownloadLibrary(
            listOf(
                download("done", Download.State.Finished),
                download("one"),
                download("two"),
                download("three"),
                download("wanted"),
            ),
        )

        assertEquals(
            listOf("done", "wanted", "one", "two", "three"),
            ids(library.promoting("wanted")),
        )
    }
}
