package app.storyarc.core.persistence

import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` task 5.9: the conflicts a sync found wait on the device until the reader
 * answers them, so a process that ends before the library shows loses no notice.
 */
class LibrarySyncStateTest {

    private val conflict = ProgressPull.Conflict(
        resolved = ReadingProgress(
            identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz"),
            position = ReadingPosition.Page(40, 100),
            updatedAtEpochMillis = 1_767_225_600_000L,
        ),
        discarded = ReadingPosition.Page(30, 100),
    )

    @Test
    fun `a pending conflict is read back by a new state over the same preferences`() {
        val preferences = FakePreferences()
        LibrarySyncState(preferences).savePendingConflicts(listOf(conflict))

        assertEquals(listOf(conflict), LibrarySyncState(preferences).pendingConflicts())
    }

    @Test
    fun `nothing is pending until a sync finds something, and nothing after the reader answers`() {
        val state = LibrarySyncState(FakePreferences())
        assertTrue(state.pendingConflicts().isEmpty())

        state.savePendingConflicts(listOf(conflict))
        state.savePendingConflicts(emptyList())

        assertTrue(state.pendingConflicts().isEmpty())
    }
}
