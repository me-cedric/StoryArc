package app.storyarc.feature.library

import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.LibrarySyncState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `library-sync` task 5.9: a conflict a sync found waits until the reader answers it.
 *
 * The cause: a background sync runs in a process with no screen, its conflicts were held in
 * memory only, and the process ended before the library showed. [SyncConflicts] now writes
 * them to [LibrarySyncState] as well, shows them again in the next process, and the reader's
 * answer clears both.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncConflictsPendingTest {

    private val conflict = ProgressPull.Conflict(
        resolved = ReadingProgress(
            identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a/Lantern Green 07.cbz"),
            position = ReadingPosition.Page(40, 100),
            updatedAtEpochMillis = 1_767_225_600_000L,
        ),
        discarded = ReadingPosition.Page(30, 100),
    )

    private val state = LibrarySyncState.open(ApplicationProvider.getApplicationContext())

    @Before
    fun wire() {
        state.savePendingConflicts(emptyList())
        SyncConflicts.pending = state
    }

    @After
    fun clear() {
        RefreshConflicts.clear()
        SyncConflicts.pending = null
    }

    @Test
    fun `what a sync reports waits on the device, and the next process shows it again`() {
        SyncConflicts.report(listOf(conflict))
        assertEquals(listOf(conflict), state.pendingConflicts())

        // The process ended: the holder is empty, the device is not.
        RefreshConflicts.report(emptyList())
        clearHolderOnly()
        SyncConflicts.restore()

        assertEquals(listOf("Lantern Green 07"), RefreshConflicts.conflicts.value.map { it.title })
        assertEquals(listOf(ReadingPosition.Page(30, 100)), RefreshConflicts.conflicts.value.map { it.discarded })
    }

    @Test
    fun `the reader's answer clears what waits`() {
        SyncConflicts.report(listOf(conflict))

        RefreshConflicts.clear()

        assertTrue(state.pendingConflicts().isEmpty())
        assertTrue(RefreshConflicts.conflicts.value.isEmpty())
    }

    /** What a process ending does to the holder: nothing is answered, the memory is gone. */
    private fun clearHolderOnly() {
        SyncConflicts.pending = null
        RefreshConflicts.clear()
        SyncConflicts.pending = state
    }
}
