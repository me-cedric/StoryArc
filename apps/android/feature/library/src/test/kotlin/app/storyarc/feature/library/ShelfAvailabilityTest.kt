package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * How much of a shelf is already here, pinned apart from any screen that draws it.
 *
 * `collections-and-reading-lists`' bulk download states a count and a size before it
 * starts; the collection, list and series headers state the same question the other way,
 * up front. iOS asserts the same cases in `ShelfAvailabilityTests`.
 */
class ShelfAvailabilityTest {

    private fun publication(id: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$id.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = id,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `every member on this device counts both the same`() {
        val members = listOf("a", "b", "c").map(::publication)
        val counted = ShelfAvailability.onDeviceCount(members) { true }
        assertEquals(3 to 3, counted)
    }

    @Test
    fun `no member on this device counts zero of the whole`() {
        val members = listOf("a", "b").map(::publication)
        val counted = ShelfAvailability.onDeviceCount(members) { false }
        assertEquals(0 to 2, counted)
    }

    @Test
    fun `a mixed shelf counts only the members the predicate accepts`() {
        val members = listOf("a", "b", "c", "d").map(::publication)
        val here = setOf(members[0].id, members[2].id)
        val counted = ShelfAvailability.onDeviceCount(members) { it.id in here }
        assertEquals(2 to 4, counted)
    }

    @Test
    fun `an empty shelf is zero of zero`() {
        val counted = ShelfAvailability.onDeviceCount(emptyList()) { true }
        assertEquals(0 to 0, counted)
    }
}
