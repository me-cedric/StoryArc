package app.storyarc.core.persistence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the reader chose on the end screen about a finished download (D7). iOS's
 * `CleanupChoicesTests` asserts the same table.
 */
class CleanupChoicesTest {
    private fun store(): CleanupChoices = CleanupChoices(FakePreferences())

    @Test
    fun `nothing kept yet holds nothing`() {
        assertFalse(store().isKept("one"))
    }

    @Test
    fun `a kept download is kept, and no other download is`() {
        val store = store()
        store.keep("one")
        assertTrue(store.isKept("one"))
        assertFalse(store.isKept("two"))
    }

    @Test
    fun `a kept download survives a fresh store over the same preferences`() {
        val preferences = FakePreferences()
        CleanupChoices(preferences).keep("one")
        assertTrue(CleanupChoices(preferences).isKept("one"))
    }

    @Test
    fun `with the sweep on, a download goes on close unless the reader kept it`() {
        val store = store()
        assertTrue(store.isRemovedOnClose("one", automaticCleanupIsOn = true))
        store.keep("one")
        assertFalse(store.isRemovedOnClose("one", automaticCleanupIsOn = true))
    }

    @Test
    fun `with the sweep off, a download goes on close only when the reader asked`() {
        val store = store()
        assertFalse(store.isRemovedOnClose("one", automaticCleanupIsOn = false))
        store.removeOnClose("one")
        assertTrue(store.isRemovedOnClose("one", automaticCleanupIsOn = false))
        assertFalse(store.isRemovedOnClose("two", automaticCleanupIsOn = false))
    }

    @Test
    fun `keep withdraws a removal the reader asked for`() {
        val store = store()
        store.removeOnClose("one")
        store.keep("one")
        assertFalse(store.isRemovedOnClose("one", automaticCleanupIsOn = false))
        assertTrue(store.takeRemovals().isEmpty())
    }

    @Test
    fun `a removal the reader asked for is handed over once, then forgotten`() {
        val store = store()
        store.removeOnClose("one")
        assertEquals(setOf("one"), store.takeRemovals())
        assertTrue(store.takeRemovals().isEmpty())
        assertFalse(store.isRemovedOnClose("one", automaticCleanupIsOn = false))
    }
}
