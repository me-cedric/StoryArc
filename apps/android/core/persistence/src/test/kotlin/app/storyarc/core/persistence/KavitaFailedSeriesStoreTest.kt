package app.storyarc.core.persistence

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which series a Kavita continuation could not read, kept so they are retried rather than
 * lost until the whole continuation runs again.
 */
class KavitaFailedSeriesStoreTest {
    private fun store() = KavitaFailedSeriesStore(FakePreferences())

    @Test
    fun `a source nothing has failed has nothing pending`() {
        assertTrue(store().pending(UUID.randomUUID()).isEmpty())
    }

    @Test
    fun `what was recorded as failing comes back whole`() {
        val store = store()
        val source = UUID.randomUUID()

        store.record(source, setOf(12, 47))

        assertEquals(setOf(12, 47), store.pending(source))
    }

    @Test
    fun `recording an empty set forgets the source, which is a retry pass that succeeded`() {
        val store = store()
        val source = UUID.randomUUID()
        store.record(source, setOf(12, 47))

        store.record(source, emptySet())

        assertTrue(store.pending(source).isEmpty())
    }

    @Test
    fun `recording replaces the whole set, for that source alone`() {
        val store = store()
        val source = UUID.randomUUID()
        val other = UUID.randomUUID()
        store.record(other, setOf(99))

        store.record(source, setOf(12, 47))
        store.record(source, setOf(47))

        assertEquals(setOf(47), store.pending(source))
        assertEquals(setOf(99), store.pending(other))
    }
}
