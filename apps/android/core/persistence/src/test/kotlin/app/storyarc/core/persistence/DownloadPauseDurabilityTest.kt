package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadHold
import app.storyarc.core.model.DownloadLibrary
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Why a download stopped, kept across a relaunch.
 *
 * `offline-downloads` requires a held queue to say what it is waiting for, and the settings
 * screen asks the *records* rather than a live queue. A record that came back queued made
 * every one of those sentences unreachable in the running app. iOS's `DownloadStoreTests`
 * asserts the same two cases.
 */
class DownloadPauseDurabilityTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun store(): DownloadStore =
        DownloadStore(FakePreferences(), folder.newFolder("downloads"))

    private fun download(id: String) = Download(
        id = id,
        title = id,
        remote = "https://example.test/$id.cbz",
        mediaType = "application/vnd.comicbook+zip",
    )

    @Test
    fun `a paused download comes back with the reason it was paused for`() {
        val store = store()
        val library = DownloadLibrary()
            .queueing(download("wifi"))
            .queueing(download("space"))
            .queueing(download("reader"))
            .marking("wifi", Download.State.Paused(Download.Pause.WAITING_FOR_WIFI))
            .marking("space", Download.State.Paused(Download.Pause.OUT_OF_SPACE))
            .marking("reader", Download.State.Paused(Download.Pause.BY_READER))
        store.save(library)

        val read = store.library()
        assertEquals(
            Download.State.Paused(Download.Pause.WAITING_FOR_WIFI),
            read["wifi"]?.state,
        )
        assertEquals(Download.State.Paused(Download.Pause.OUT_OF_SPACE), read["space"]?.state)
        assertEquals(Download.State.Paused(Download.Pause.BY_READER), read["reader"]?.state)
        assertEquals(DownloadHold.OUT_OF_SPACE, read.hold(null))
    }

    @Test
    fun `a record written before the reason was kept comes back queued`() {
        // Written by a build that had no pause field. Decoding has to tolerate its absence,
        // because the alternative is a reader whose whole download list disappears.
        val store = store()
        store.save(DownloadLibrary().queueing(download("a")))
        assertEquals(Download.State.Queued, store.library()["a"]?.state)
    }
}
