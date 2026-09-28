package app.storyarc.core.persistence

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Downloads exempted from the automatic sweep (D7's "Keep" action). */
class KeptFromCleanupTest {
    private fun store(): KeptFromCleanup = KeptFromCleanup(FakePreferences())

    @Test
    fun `nothing kept yet holds nothing`() {
        assertFalse(store().contains("one"))
    }

    @Test
    fun `a kept download is kept, and no other download is`() {
        val store = store()
        store.keep("one")
        assertTrue(store.contains("one"))
        assertFalse(store.contains("two"))
    }

    @Test
    fun `keeping the same download twice changes nothing`() {
        val store = store()
        store.keep("one")
        store.keep("one")
        assertTrue(store.contains("one"))
    }

    @Test
    fun `a kept download survives a fresh store over the same preferences`() {
        val preferences = FakePreferences()
        KeptFromCleanup(preferences).keep("one")
        assertTrue(KeptFromCleanup(preferences).contains("one"))
    }
}
