package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.UUID

/**
 * Which sentence the removal confirmation shows, and where its figures come from.
 *
 * `sources`, *Removing a source*: the app "states how many downloaded files and how much disk
 * space will be freed before asking for confirmation". The confirmation used to say that no
 * files are deleted whatever the source held, so every case here is one clause of that
 * scenario. iOS's `SourceRemovalWordingTests` asserts the same table in the same order.
 *
 * **Mutation-proved on 2026-09-05**: with the rule changed to `downloadCount > 1`, the two
 * cases built on one download — `one finished download is enough…` and `a finished download
 * that weighs nothing…` — failed by name and the other four stayed green; reverted.
 */
class SourceRemovalWordingTest {

    @Test
    fun `nothing downloaded picks the sentence that names only the titles`() {
        val wording = SourceRemovalWording.of(titleCount = 12, downloadCount = 0, downloadedBytes = 0L)

        assertEquals(SourceRemovalWording.TitlesOnly(12), wording)
    }

    @Test
    fun `one finished download is enough to name the files and what they weigh`() {
        // The defect, stated as the assertion. One file on disk is the smallest source for
        // which "no files on your device are deleted" is false.
        val wording = SourceRemovalWording.of(titleCount = 3, downloadCount = 1, downloadedBytes = 5_242_880L)

        assertEquals(SourceRemovalWording.TitlesAndDownloads(3, 1, 5_242_880L), wording)
    }

    @Test
    fun `the figures are the arguments' own, neither rounded nor recounted`() {
        val wording = SourceRemovalWording.of(titleCount = 7, downloadCount = 4, downloadedBytes = 1_234L)

        val withDownloads = wording as SourceRemovalWording.TitlesAndDownloads
        assertEquals(7, withDownloads.titleCount)
        assertEquals(4, withDownloads.downloadCount)
        assertEquals(1_234L, withDownloads.downloadedBytes)
    }

    @Test
    fun `a finished download that weighs nothing is still a file the removal deletes`() {
        // Decided by the count, not the bytes: the sentence for zero bytes would otherwise
        // promise that nothing is deleted while a file goes.
        val wording = SourceRemovalWording.of(titleCount = 1, downloadCount = 1, downloadedBytes = 0L)

        assertEquals(SourceRemovalWording.TitlesAndDownloads(1, 1, 0L), wording)
    }

    @Test
    fun `from a diagnosis, the figures are the source's own finished downloads`() {
        // The same filter the *Downloaded* field uses, so the two cannot disagree: this
        // source's finished downloads count, another source's and a queued one do not.
        val mine = Source(displayName = "Comics", kind = SourceKind.KAVITA_SERVER, state = SourceConnectionState.Connected)
        val diagnosis = SourceDiagnosis.of(
            mine,
            itemCount = 5,
            downloads = listOf(
                download(mine.id, 100L),
                download(mine.id, 200L),
                download(UUID.randomUUID(), 4_000L),
                download(mine.id, 50L, Download.State.Queued),
            ),
        )

        assertEquals(SourceRemovalWording.TitlesAndDownloads(5, 2, 300L), SourceRemovalWording.of(diagnosis))
    }

    @Test
    fun `a diagnosis with nothing on disk reads as titles only`() {
        val source = Source(displayName = "Attic", kind = SourceKind.NETWORK_SHARE, state = SourceConnectionState.Connected)
        val diagnosis = SourceDiagnosis.of(source, itemCount = 9, downloads = emptyList())

        assertEquals(SourceRemovalWording.TitlesOnly(9), SourceRemovalWording.of(diagnosis))
    }

    private fun download(
        sourceId: UUID?,
        bytes: Long,
        state: Download.State = Download.State.Finished,
    ) = Download(
        id = UUID.randomUUID().toString(),
        sourceId = sourceId,
        title = "Issue",
        remote = "file:///tmp/issue.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = state,
        downloadedBytes = bytes,
    )
}
