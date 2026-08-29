package app.storyarc.core.persistence

import app.storyarc.core.model.Bookmark
import app.storyarc.core.model.markAt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors iOS's `BookmarkStoreTests`, assertion for assertion. */
class BookmarkStoreTest {

    private fun store() = BookmarkStore(FakePreferences())

    private fun mark(
        id: String = "mark-1",
        progression: Double,
        resource: String = "ch1.xhtml",
        chapter: String = "Chapter One",
        excerpt: String = "Text long enough that pagination has something to do with it.",
        madeAt: Long = 0,
    ) = Bookmark(
        id = id,
        locator = """{"href":"$resource"}""",
        resource = resource,
        progression = progression,
        chapter = chapter,
        excerpt = excerpt,
        createdAtEpochMillis = madeAt,
    )

    @Test
    fun `a mark is kept, with the chapter and the excerpt the spec asks for`() {
        val store = store()
        store.toggle(mark(progression = 0.25), publication = "book")

        val kept = store.bookmarks("book").first()
        assertEquals("Chapter One", kept.chapter)
        assertTrue(kept.excerpt.startsWith("Text long enough"))
        assertEquals(0.25, kept.progression, 0.0)
    }

    @Test
    fun `pressing the control again on the same page removes the mark`() {
        val store = store()
        store.toggle(mark(progression = 0.25), publication = "book")
        store.toggle(mark(id = "mark-2", progression = 0.25), publication = "book")

        assertTrue(store.bookmarks("book").isEmpty())
    }

    @Test
    fun `the same fraction in another chapter is another place`() {
        val store = store()
        store.toggle(mark(progression = 0.25, resource = "ch1.xhtml"), publication = "book")
        store.toggle(
            mark(id = "mark-2", progression = 0.25, resource = "ch2.xhtml"),
            publication = "book",
        )

        assertEquals(2, store.bookmarks("book").size)
    }

    @Test
    fun `the list reads in book order, not in the order the marks were made`() {
        val store = store()
        store.toggle(mark(progression = 0.90, madeAt = 10), publication = "book")
        store.toggle(mark(id = "mark-2", progression = 0.10, madeAt = 20), publication = "book")

        assertEquals(listOf(0.10, 0.90), store.bookmarks("book").map { it.progression })
    }

    @Test
    fun `one publication's marks are not another's`() {
        val store = store()
        store.toggle(mark(progression = 0.25), publication = "one")

        assertTrue(store.bookmarks("two").isEmpty())
    }

    @Test
    fun `removing the last mark leaves nothing behind for that publication`() {
        val store = store()
        val only = mark(progression = 0.25)
        store.toggle(only, publication = "book")

        assertTrue(store.remove(only.id, publication = "book").isEmpty())
        assertTrue(store.bookmarks("book").isEmpty())
    }

    @Test
    fun `marks survive being read back through a second store`() {
        val preferences = FakePreferences()
        BookmarkStore(preferences).toggle(mark(progression = 0.25), publication = "book")

        assertEquals(1, BookmarkStore(preferences).bookmarks("book").size)
    }

    @Test
    fun `a mark is found again at the fraction it was made at`() {
        val store = store()
        store.toggle(mark(progression = 0.25), publication = "book")

        val marks = store.bookmarks("book")
        assertNotNull(marks.markAt(0.25, "ch1.xhtml"))
        assertNull(marks.markAt(0.26, "ch1.xhtml"))
    }
}
