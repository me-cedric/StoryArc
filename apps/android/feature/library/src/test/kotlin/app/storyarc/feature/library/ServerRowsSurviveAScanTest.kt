package app.storyarc.feature.library

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * A folder walk never deletes a server's rows.
 *
 * The library now holds publications no walk produced. [ScanReconciliation] exists to remove
 * what a walk looked for and did not find, and the danger is obvious: a round that covers
 * one folder must not conclude that a Kavita server's four hundred rows have vanished.
 *
 * It holds by construction rather than by a branch -- `vanished` only considers a source
 * that appears in `seenBySource`, and a server appears in no walk -- which is exactly why it
 * is worth pinning. The rule is one line and the next person to touch it will not know a
 * server's rows depend on it.
 *
 * `sources`: "a failed refresh and an emptied source are different things".
 */
class ServerRowsSurviveAScanTest {

    private val folder = UUID.randomUUID()
    private val server = UUID.randomUUID()

    @Test
    fun `a walk over one folder leaves a server's rows alone`() {
        val gone = ScanReconciliation.vanished(
            seenBySource = mapOf(folder to setOf("a", "b")),
            shelved = listOf("a" to folder, "b" to folder, "chapter-1" to server, "chapter-2" to server),
            partial = emptySet(),
        )

        assertEquals(emptyList<String>(), gone)
    }

    @Test
    fun `a walk still removes what its own folder no longer holds`() {
        val gone = ScanReconciliation.vanished(
            seenBySource = mapOf(folder to setOf("a")),
            shelved = listOf("a" to folder, "b" to folder, "chapter-1" to server),
            partial = emptySet(),
        )

        assertEquals(listOf("b"), gone)
    }

    @Test
    fun `a server that answered nothing loses nothing`() {
        // The contributor returns an empty list -- refused, unreachable, or genuinely empty.
        // It never reaches `seenBySource`, so there is no answer to reconcile against.
        val gone = ScanReconciliation.vanished(
            seenBySource = mapOf(folder to setOf("a")),
            shelved = listOf("a" to folder, "chapter-1" to server),
            partial = emptySet(),
        )

        assertEquals(emptyList<String>(), gone.filter { it.startsWith("chapter") })
    }
}
