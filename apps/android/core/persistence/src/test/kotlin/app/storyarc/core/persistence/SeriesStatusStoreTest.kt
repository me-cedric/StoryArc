package app.storyarc.core.persistence

import app.storyarc.core.model.PublicationStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A status the reader set by hand, for a series whose source reports none.
 *
 * iOS's `SeriesStatusStoreTests` makes the same claims in the same order.
 */
class SeriesStatusStoreTest {

    private fun store() = SeriesStatusStore(FakePreferences())

    @Test
    fun `a status survives a round trip`() {
        val store = store()
        store.set("Tidal Reach", PublicationStatus.COMPLETED)
        assertEquals(mapOf("Tidal Reach" to PublicationStatus.COMPLETED), store.all())
    }

    @Test
    fun `setting a status again for the same series replaces it`() {
        val store = store()
        store.set("Tidal Reach", PublicationStatus.ONGOING)
        store.set("Tidal Reach", PublicationStatus.HIATUS)
        assertEquals(mapOf("Tidal Reach" to PublicationStatus.HIATUS), store.all())
    }

    @Test
    fun `two series keep their own statuses apart`() {
        val store = store()
        store.set("Tidal Reach", PublicationStatus.ONGOING)
        store.set("Nightglass", PublicationStatus.COMPLETED)
        assertEquals(
            mapOf("Tidal Reach" to PublicationStatus.ONGOING, "Nightglass" to PublicationStatus.COMPLETED),
            store.all(),
        )
    }

    @Test
    fun `clearing a series removes only that one`() {
        val store = store()
        store.set("Tidal Reach", PublicationStatus.ONGOING)
        store.set("Nightglass", PublicationStatus.COMPLETED)
        store.clear("Tidal Reach")
        assertEquals(mapOf("Nightglass" to PublicationStatus.COMPLETED), store.all())
    }

    @Test
    fun `a store that was never written to holds nothing`() {
        assertTrue(store().all().isEmpty())
    }
}
