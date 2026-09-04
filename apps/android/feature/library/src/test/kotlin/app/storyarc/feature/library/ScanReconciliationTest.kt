package app.storyarc.feature.library

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/** Which rows a finished scan is entitled to take away, and which it is not. */
class ScanReconciliationTest {

    private val comics = UUID.fromString("00000000-0000-0000-0000-0000000000c0")
    private val audiobooks = UUID.fromString("00000000-0000-0000-0000-0000000000a0")
    private val kavita = UUID.fromString("00000000-0000-0000-0000-0000000000ca")

    @Test
    fun aBookTheWalkNoLongerFindsIsRemoved() {
        val vanished = ScanReconciliation.vanished(
            seenBySource = mapOf(comics to setOf("kept")),
            shelved = listOf("kept" to comics, "deleted" to comics),
        )

        assertEquals(listOf("deleted"), vanished)
    }

    @Test
    fun aWalkThatFoundNothingRemovesNothingOfItsOwn() {
        // A folder whose permission lapsed lists as empty. It is not a reader who deleted
        // every book they own, and treating it as one empties the shelf.
        val vanished = ScanReconciliation.vanished(
            seenBySource = mapOf(comics to emptySet()),
            shelved = listOf("one" to comics, "two" to comics),
        )

        assertEquals(emptyList<String>(), vanished)
    }

    @Test
    fun oneFolderAnsweringDoesNotEmptyAnotherThatCouldNotBeRead() {
        // The regression the app's-own-folder walk would otherwise have introduced: the
        // managed folder always answers, so before this the first unreadable picked folder
        // lost every book in it the moment any scan finished.
        val vanished = ScanReconciliation.vanished(
            seenBySource = mapOf(null to setOf("shared"), comics to emptySet()),
            shelved = listOf("shared" to null, "one" to comics, "two" to comics),
        )

        assertEquals(emptyList<String>(), vanished)
    }

    @Test
    fun aFolderWalkNeverRemovesAServersDownloads() {
        // Nothing walks a Kavita server, so a folder scan has no evidence about what it
        // holds. Before this, finishing any scan took every kept chapter off the shelf.
        val vanished = ScanReconciliation.vanished(
            seenBySource = mapOf(comics to setOf("local")),
            shelved = listOf("local" to comics, "chapter" to kavita),
        )

        assertEquals(emptyList<String>(), vanished)
    }

    @Test
    fun eachSourceIsReconciledAgainstItsOwnWalk() {
        val vanished = ScanReconciliation.vanished(
            seenBySource = mapOf(comics to setOf("kept"), audiobooks to setOf("heard")),
            shelved = listOf(
                "kept" to comics,
                "gone" to comics,
                "heard" to audiobooks,
                "lost" to audiobooks,
            ),
        )

        assertEquals(listOf("gone", "lost"), vanished)
    }

    @Test
    fun theAppsOwnFolderReconcilesTheRowsThatBelongToNoSource() {
        val vanished = ScanReconciliation.vanished(
            seenBySource = mapOf(null to setOf("still-there")),
            shelved = listOf("still-there" to null, "removed" to null),
        )

        assertEquals(listOf("removed"), vanished)
    }
}
