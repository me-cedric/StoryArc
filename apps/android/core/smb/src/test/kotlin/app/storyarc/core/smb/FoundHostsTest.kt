package app.storyarc.core.smb

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * [FoundHosts] -- the table one discovery keeps while hosts answer and drop out.
 *
 * Plain values stand in for the `NsdServiceInfo` a JVM test cannot build: the rules here are
 * about names, order and replacement, and a name carries all three.
 */
class FoundHostsTest {

    @Test
    fun `a resolved host joins the list`() {
        val found = FoundHosts()

        assertEquals(listOf(SmbHost("attic", "10.0.0.2", 445)), found.resolved("attic", "10.0.0.2", 445))
    }

    @Test
    fun `a second host joins the first rather than replacing it`() {
        // The defect this table was extracted for: a second share answering is the ordinary
        // case on a home network, not an edge.
        val found = FoundHosts()
        found.resolved("attic", "10.0.0.2", 445)

        assertEquals(
            listOf(SmbHost("attic", "10.0.0.2", 445), SmbHost("cellar", "10.0.0.3", 445)),
            found.resolved("cellar", "10.0.0.3", 445),
        )
    }

    @Test
    fun `hosts stay in the order they answered`() {
        val found = FoundHosts()
        found.resolved("cellar", "10.0.0.3", 445)
        found.resolved("attic", "10.0.0.2", 445)

        assertEquals(
            listOf("cellar", "attic"),
            found.resolved("shed", "10.0.0.4", 445).dropLast(1).map { it.name },
        )
    }

    @Test
    fun `a host that answers twice is recorded once, at its newest address`() {
        // A host can answer again after a network change, and the list is drawn as rows a
        // reader picks from: the same share twice is two rows that do the same thing.
        val found = FoundHosts()
        found.resolved("attic", "10.0.0.2", 445)

        assertEquals(listOf(SmbHost("attic", "10.0.0.9", 445)), found.resolved("attic", "10.0.0.9", 445))
    }

    @Test
    fun `a lost host leaves the list and the others keep their order`() {
        val found = FoundHosts()
        found.resolved("attic", "10.0.0.2", 445)
        found.resolved("cellar", "10.0.0.3", 445)
        found.resolved("shed", "10.0.0.4", 445)

        assertEquals(listOf("attic", "shed"), found.lost("cellar").map { it.name })
    }

    @Test
    fun `losing a host this discovery never resolved is not an error`() {
        // `onServiceLost` can arrive for a service whose resolve never landed, so this is a
        // real arrival rather than a defensive branch.
        val found = FoundHosts()
        found.resolved("attic", "10.0.0.2", 445)

        assertEquals(listOf(SmbHost("attic", "10.0.0.2", 445)), found.lost("cellar"))
    }
}
