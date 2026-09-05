package app.storyarc

import app.storyarc.core.model.Download
import app.storyarc.core.persistence.ImportedCopies
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which question a reader is being asked when they press *Stop*, *Remove* or *Remove download*.
 *
 * The Downloads destination asked one question for every act. *Stop* on a row that was still
 * arriving put up *Remove this download?* — "This deletes the copy of Harbour Lights 03 on
 * this device. Your reading position is kept, and it can be downloaded again." — over a
 * transfer with no copy on the device and no reading position to keep. One string doing two
 * jobs, and both sentences of it false in the case the September sweep photographed.
 *
 * iOS's `DownloadQueueRemovalTests` is this suite, case for case, minus [DISCARDING] — which
 * exists here because this platform's queue row offers *Remove* on a failed transfer and
 * iOS's does not.
 */
class DownloadQueueRemovalTest {

    /** The defect, stated as a test: a transfer under way is stopped, not removed. */
    @Test
    fun `a transfer that has not landed is a stop`() {
        val moving = listOf(
            Download.State.Queued,
            Download.State.Running,
            Download.State.Paused(Download.Pause.BY_READER),
            Download.State.Paused(Download.Pause.WAITING_FOR_WIFI),
            Download.State.Paused(Download.Pause.OUT_OF_SPACE),
        )
        moving.forEach { state ->
            assertEquals(
                "$state is a transfer that has not landed",
                DownloadQueueRemoval.STOPPING,
                DownloadQueueRemoval.of(download(state)),
            )
        }
    }

    /**
     * And one that stopped by itself is neither.
     *
     * "This stops the transfer" is as untrue of a failed download as the removal sentence is
     * of a running one — the transfer stopped three attempts ago. The row offers *Remove*
     * here rather than *Stop*, so the question has to be a removal that promises nothing
     * about a copy.
     */
    @Test
    fun `a failed transfer is discarded, not stopped`() {
        val failed = Download.State.Failed(reason = "The server did not answer in time.", attempts = 3)
        assertEquals(DownloadQueueRemoval.DISCARDING, DownloadQueueRemoval.of(download(failed)))
    }

    /** A finished download is the case the old string was actually written for. */
    @Test
    fun `a finished download is a removal`() {
        assertEquals(
            DownloadQueueRemoval.REMOVING,
            DownloadQueueRemoval.of(download(Download.State.Finished)),
        )
    }

    /**
     * And an import is the third case, which `local-library` asks more words of than either
     * of the other two.
     */
    @Test
    fun `a finished import names the original it is not touching`() {
        val copy = download(Download.State.Finished, sourceId = ImportedCopies.SOURCE_ID)
        assertEquals(DownloadQueueRemoval.REMOVING_IMPORT, DownloadQueueRemoval.of(copy))
    }

    /**
     * **The ordering, which is the whole reason this is a type and not an `if` in a view.**
     *
     * An import is written into the record as `Queued` and marked finished a line later, so a
     * record caught between the two — a crash mid-import, a build that saved before it marked
     * — is an import that has not landed. Nothing about it is on the device to free, so it is
     * a stop, and the import sentence promising to free a size would be naming a size the
     * reader would not get back.
     */
    @Test
    fun `an import that has not landed is still a stop`() {
        val copy = download(Download.State.Queued, sourceId = ImportedCopies.SOURCE_ID)
        assertEquals(DownloadQueueRemoval.STOPPING, DownloadQueueRemoval.of(copy))
    }

    private fun download(
        state: Download.State,
        sourceId: UUID? = UUID.fromString("0f2b6a1e-1111-4111-8111-111111111111"),
    ) = Download(
        id = "one",
        sourceId = sourceId,
        title = TITLE,
        remote = "https://example.invalid/hl03.epub",
        mediaType = "application/epub+zip",
        state = state,
        expectedBytes = 8_400_000,
        downloadedBytes = 3_100_000,
    )

    private companion object {
        /** The title the sweep photographed the wrong sentence about. */
        const val TITLE = "Harbour Lights 03"
    }
}
