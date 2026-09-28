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
    fun `nothing stored reads as no fraction, not zero`() {
        assertNull(ScrollOffsetMemory().fraction(comic))
    }

    @Test
    fun `a remembered fraction comes back for that publication and no other`() {
        val memory = ScrollOffsetMemory().remembering(comic, 0.42f)
        assertEquals(0.42f, memory.fraction(comic)!!, 0.001f)
        assertNull(memory.fraction(novel))
    }

    @Test
    fun `remembering again for the same publication replaces it`() {
        val memory = ScrollOffsetMemory()
            .remembering(comic, 0.2f)
            .remembering(comic, 0.9f)
        assertEquals(0.9f, memory.fraction(comic)!!, 0.001f)
    }

    @Test
    fun `a fraction outside 0 to 1 is clamped before it is kept`() {
        val memory = ScrollOffsetMemory().remembering(comic, 4f)
        assertEquals(1f, memory.fraction(comic)!!, 0.001f)
    }
}
