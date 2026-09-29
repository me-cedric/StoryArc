package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Where a continuous scroll sits within its current page, kept only on this device.
 * iOS's `ScrollOffsetMemoryTests` asserts the same table.
 */
class ScrollOffsetMemoryTest {
    private val comic = PublicationIdentity(normalizedPath = "/comics/one.cbz")
    private val novel = PublicationIdentity(normalizedPath = "/books/two.epub")

    @Test
    fun `nothing stored reads as no entry, not zero`() {
        assertNull(ScrollOffsetMemory().entry(comic))
    }

    @Test
    fun `a remembered place comes back for that publication and no other`() {
        val memory = ScrollOffsetMemory().remembering(comic, 0.42f, page = 3)
        assertEquals(ScrollOffsetMemory.Entry(3, 0.42f), memory.entry(comic))
        assertNull(memory.entry(novel))
    }

    @Test
    fun `remembering again for the same publication replaces the page and the fraction`() {
        val memory = ScrollOffsetMemory()
            .remembering(comic, 0.2f, page = 1)
            .remembering(comic, 0.9f, page = 4)
        assertEquals(ScrollOffsetMemory.Entry(4, 0.9f), memory.entry(comic))
    }

    @Test
    fun `a fraction outside 0 to 1 is clamped before it is kept`() {
        val memory = ScrollOffsetMemory().remembering(comic, 4f, page = 0)
        assertEquals(1f, memory.entry(comic)!!.fraction, 0.001f)
    }
}
