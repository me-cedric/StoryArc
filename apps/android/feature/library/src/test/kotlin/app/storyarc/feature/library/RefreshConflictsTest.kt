package app.storyarc.feature.library

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The holder task 2.9 added so a conflict a background refresh finds reaches the library
 * screen, not only the series screen's own pull. [LibraryViewModel] cannot hold this state
 * itself — it is at its line cap (`scripts/line-cap.mjs`) — so [RefreshConflicts] is a plain
 * object beside it, proved on its own here with no `ViewModel` or `Application` in the way.
 */
class RefreshConflictsTest {

    private fun conflict(title: String = "Lantern Green #7") = KavitaConflict(
        title = title,
        resolved = ReadingProgress(
            identity = PublicationIdentity(normalizedPath = "/a.cbz"),
            position = ReadingPosition.Page(index = 10, total = 20),
            updatedAtEpochMillis = 0L,
        ),
        discarded = ReadingPosition.Page(index = 3, total = 20),
    )

    // Every test starts from, and must leave, an empty holder: this is process-wide state,
    // the same reason `SmbSourceRegistry` and `SmbNetworkWatch` are.
    @After
    fun clear() {
        RefreshConflicts.clear()
    }

    @Test
    fun `a report with nothing in it is not a report at all`() = runTest {
        RefreshConflicts.report(emptyList())

        assertTrue(RefreshConflicts.conflicts.value.isEmpty())
    }

    @Test
    fun `what one refresh found is what the holder then carries`() = runTest {
        val found = listOf(conflict())

        RefreshConflicts.report(found)

        assertEquals(found, RefreshConflicts.conflicts.value)
    }

    @Test
    fun `a second source's conflicts join the first refresh's, rather than replacing them`() = runTest {
        RefreshConflicts.report(listOf(conflict("Lantern Green #7")))
        RefreshConflicts.report(listOf(conflict("Night Market #2")))

        assertEquals(2, RefreshConflicts.conflicts.value.size)
    }

    @Test
    fun `the reader answering clears every conflict the holder had`() = runTest {
        RefreshConflicts.report(listOf(conflict()))

        RefreshConflicts.clear()

        assertTrue(RefreshConflicts.conflicts.value.isEmpty())
    }
}
