package app.storyarc.core.persistence

import app.storyarc.core.model.Annotation
import app.storyarc.core.model.HighlightColour
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors iOS's `AnnotationStoreTests`, assertion for assertion. */
class AnnotationStoreTest {

    private fun store() = AnnotationStore(FakePreferences())

    private fun mark(
        id: String = "mark-1",
        text: String = "Call me Ishmael",
        note: String = "",
        colour: HighlightColour = HighlightColour.YELLOW,
        progression: Double = 0.25,
    ) = Annotation(
        id = id,
        locator = "{}",
        resource = "ch1.xhtml",
        progression = progression,
        chapter = "Chapter One",
        text = text,
        colour = colour,
        note = note,
        createdAtEpochMillis = (progression * 1000).toLong(),
    )

    @Test
    fun `a highlight is kept with its words and its colour`() {
        val store = store()
        store.save(mark(colour = HighlightColour.GREEN), "book")

        val kept = store.annotations("book").first()
        assertEquals("Call me Ishmael", kept.text)
        assertEquals(HighlightColour.GREEN, kept.colour)
        assertFalse(kept.hasNote)
    }

    @Test
    fun `writing on a highlight replaces it rather than making a second one`() {
        val store = store()
        store.save(mark(), "book")
        store.save(mark(note = "The famous opening"), "book")

        val marks = store.annotations("book")
        assertEquals(1, marks.size)
        assertEquals("The famous opening", marks.first().note)
    }

    @Test
    fun `two marks on different words are two marks`() {
        val store = store()
        store.save(mark(id = "a", text = "first", progression = 0.1), "book")
        store.save(mark(id = "b", text = "second", progression = 0.2), "book")

        assertEquals(2, store.annotations("book").size)
    }

    @Test
    fun `the list reads in book order, not in the order the marks were made`() {
        val store = store()
        store.save(mark(id = "a", text = "later", progression = 0.9), "book")
        store.save(mark(id = "b", text = "earlier", progression = 0.1), "book")

        assertEquals(listOf("earlier", "later"), store.annotations("book").map { it.text })
    }

    @Test
    fun `one publication's marks are not another's`() {
        val store = store()
        store.save(mark(), "one")

        assertTrue(store.annotations("two").isEmpty())
    }

    @Test
    fun `removing the last mark leaves nothing behind for that publication`() {
        val store = store()
        store.save(mark(), "book")

        assertTrue(store.remove("mark-1", "book").isEmpty())
    }

    @Test
    fun `marks survive being read back through a second store`() {
        val preferences = FakePreferences()
        AnnotationStore(preferences).save(mark(note = "kept"), "book")

        assertEquals("kept", AnnotationStore(preferences).annotations("book").first().note)
    }

    @Test
    fun `clearing a publication takes its marks and leaves the others`() {
        val store = store()
        store.save(mark(), "one")
        store.save(mark(), "two")
        store.clear("one")

        assertTrue(store.annotations("one").isEmpty())
        assertEquals(1, store.annotations("two").size)
    }
}
