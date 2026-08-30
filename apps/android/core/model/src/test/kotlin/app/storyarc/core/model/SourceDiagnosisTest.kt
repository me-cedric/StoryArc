package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

/**
 * What a source's detail screen says about a source, and what it offers to do.
 *
 * `sources` names five fields and five actions. The audit found the settings list carrying
 * two of the fields and one of the actions, so every case here is a clause of the
 * `Diagnosing a source` scenario. iOS's `SourceDiagnosisTests` asserts the same table in the
 * same order.
 */
class SourceDiagnosisTest {

    private fun source(
        name: String = "Comics",
        kind: SourceKind = SourceKind.KAVITA_SERVER,
        state: SourceConnectionState = SourceConnectionState.Connected,
        syncedAt: Long? = null,
    ) = Source(
        displayName = name,
        kind = kind,
        state = state,
        lastSuccessfulSyncEpochMillis = syncedAt,
    )

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

    // The five fields

    @Test
    fun `the state and the last successful sync are the source's own`() {
        val diagnosis = SourceDiagnosis.of(
            source(state = SourceConnectionState.Connected, syncedAt = 1_000L),
            itemCount = 4,
            downloads = emptyList(),
        )

        assertEquals(SourceConnectionState.Connected, diagnosis.state)
        assertEquals(1_000L, diagnosis.lastSuccessfulSyncEpochMillis)
        assertEquals(4, diagnosis.itemCount)
    }

    @Test
    fun `a connected source has no error to report`() {
        assertNull(
            SourceDiagnosis.of(
                source(state = SourceConnectionState.Connected),
                itemCount = 0,
                downloads = emptyList(),
            ).failure,
        )
        assertNull(
            SourceDiagnosis.of(
                source(state = SourceConnectionState.Connecting),
                itemCount = 0,
                downloads = emptyList(),
            ).failure,
        )
    }

    @Test
    fun `an unreachable source reports when it stopped answering`() {
        val diagnosis = SourceDiagnosis.of(
            source(state = SourceConnectionState.Unreachable(90L)),
            itemCount = 0,
            downloads = emptyList(),
        )

        assertEquals(SourceFailure.Unreachable(90L), diagnosis.failure)
    }

    @Test
    fun `a refused credential reports the reason, which is what a reader can act on`() {
        val diagnosis = SourceDiagnosis.of(
            source(state = SourceConnectionState.Unauthorized("Key refused")),
            itemCount = 0,
            downloads = emptyList(),
        )

        assertEquals(SourceFailure.Unauthorized("Key refused"), diagnosis.failure)
    }

    @Test
    fun `the bytes are this source's finished downloads and nobody else's`() {
        val mine = source()
        val other = UUID.randomUUID()

        val diagnosis = SourceDiagnosis.of(
            mine,
            itemCount = 3,
            downloads = listOf(
                download(mine.id, 100),
                download(mine.id, 200),
                // Another source's, and one of this source's that is not on disk yet.
                download(other, 4_000),
                download(mine.id, 50, Download.State.Queued),
            ),
        )

        assertEquals(2, diagnosis.downloadCount)
        assertEquals(300L, diagnosis.downloadedBytes)
    }

    // The five actions

    @Test
    fun `a source with downloads offers all five actions, destructive last`() {
        val mine = source()

        val diagnosis = SourceDiagnosis.of(
            mine,
            itemCount = 1,
            downloads = listOf(download(mine.id, 10)),
        )

        assertEquals(
            listOf(
                SourceAction.TEST_CONNECTION,
                SourceAction.REFRESH,
                SourceAction.CLEAR_CACHE,
                SourceAction.REMOVE_DOWNLOADS,
                SourceAction.REMOVE,
            ),
            diagnosis.actions,
        )
    }

    @Test
    fun `nothing downloaded means nothing to offer to delete`() {
        val diagnosis = SourceDiagnosis.of(source(), itemCount = 1, downloads = emptyList())

        assertFalse(diagnosis.actions.contains(SourceAction.REMOVE_DOWNLOADS))
    }

    @Test
    fun `a source the reader did not add is not one they can remove`() {
        val diagnosis = SourceDiagnosis.of(
            source("On this device", kind = SourceKind.LOCAL_FOLDER),
            itemCount = 2,
            downloads = emptyList(),
            isRemovable = false,
        )

        assertEquals(
            listOf(SourceAction.TEST_CONNECTION, SourceAction.REFRESH, SourceAction.CLEAR_CACHE),
            diagnosis.actions,
        )
    }

    @Test
    fun `only the two that delete bytes ask before they happen`() {
        assertEquals(
            listOf(SourceAction.REMOVE_DOWNLOADS, SourceAction.REMOVE),
            SourceAction.entries.filter { it.isDestructive },
        )
    }
}
