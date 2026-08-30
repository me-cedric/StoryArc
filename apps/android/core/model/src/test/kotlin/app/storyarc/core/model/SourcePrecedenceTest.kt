package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * Which of two sources holding one publication wins.
 *
 * `sources` says the reader's order decides it. The order persisted and nothing read it, so
 * every case here is the `Reordering sources` scenario's second clause. iOS's
 * `SourcePrecedenceTests` asserts the same table in the same order.
 */
class SourcePrecedenceTest {

    private val first = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER)
    private val second = Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER)
    private val registry = listOf(first, second)

    @Test
    fun `the source the reader put higher wins the title`() {
        assertTrue(SourcePrecedence.prefers(first.id, second.id, registry))
    }

    @Test
    fun `a lower source does not take a title off a higher one`() {
        assertFalse(SourcePrecedence.prefers(second.id, first.id, registry))
    }

    @Test
    fun `a second find through the same source changes nothing`() {
        assertFalse(SourcePrecedence.prefers(first.id, first.id, registry))
    }

    @Test
    fun `a publication that came through a source beats one that came through none`() {
        // A file in the app's own folder is not a library the reader configured.
        assertTrue(SourcePrecedence.prefers(second.id, null, registry))
        assertFalse(SourcePrecedence.prefers(null, second.id, registry))
    }

    @Test
    fun `a source the registry no longer holds ranks with the unattributed`() {
        val removed = UUID.randomUUID()

        assertEquals(Int.MAX_VALUE, SourcePrecedence.rank(removed, registry))
        assertEquals(Int.MAX_VALUE, SourcePrecedence.rank(null, registry))
        assertFalse(SourcePrecedence.prefers(removed, second.id, registry))
    }

    @Test
    fun `rank is the position in the registry, which is what a drag changes`() {
        assertEquals(0, SourcePrecedence.rank(first.id, registry))
        assertEquals(1, SourcePrecedence.rank(second.id, registry))

        // The same two sources, dragged the other way round.
        val dragged = listOf(second, first)
        assertEquals(1, SourcePrecedence.rank(first.id, dragged))
        assertTrue(SourcePrecedence.prefers(second.id, first.id, dragged))
    }
}
