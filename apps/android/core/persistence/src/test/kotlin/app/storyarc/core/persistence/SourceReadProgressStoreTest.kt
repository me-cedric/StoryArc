package app.storyarc.core.persistence

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a source's continuation wrote down, and what a relaunch reads back.
 *
 * `sources`' *More from a source than the library holds*: the continuation used to live only
 * in memory, so a relaunch forgot which page a partial source was on and started its
 * background read over from page two. iOS's `SourceReadProgressStoreTests` asserts the same
 * cases.
 */
class SourceReadProgressStoreTest {
    private fun store() = SourceReadProgressStore(FakePreferences())

    @Test
    fun `a source nothing has read has nothing to resume`() {
        assertNull(store().progress(UUID.randomUUID()))
    }

    @Test
    fun `what a continuation recorded comes back whole`() {
        val store = store()
        val source = UUID.randomUUID()

        store.record(source, StoredSourceProgress(read = 120, total = 215, nextPage = 3))

        assertEquals(StoredSourceProgress(read = 120, total = 215, nextPage = 3), store.progress(source))
    }

    @Test
    fun `recording again replaces the earlier progress, for that source alone`() {
        val store = store()
        val source = UUID.randomUUID()
        val other = UUID.randomUUID()
        store.record(other, StoredSourceProgress(read = 60, total = null, nextPage = 2))

        store.record(source, StoredSourceProgress(read = 60, total = null, nextPage = 2))
        store.record(source, StoredSourceProgress(read = 120, total = 154, nextPage = 3))

        assertEquals(StoredSourceProgress(read = 120, total = 154, nextPage = 3), store.progress(source))
        assertEquals(StoredSourceProgress(read = 60, total = null, nextPage = 2), store.progress(other))
    }

    @Test
    fun `a finished source is forgotten`() {
        val store = store()
        val source = UUID.randomUUID()
        store.record(source, StoredSourceProgress(read = 154, total = 154, nextPage = 4))

        store.clear(source)

        assertNull(store.progress(source))
    }
}
