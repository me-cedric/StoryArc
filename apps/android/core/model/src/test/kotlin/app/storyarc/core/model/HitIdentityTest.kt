package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * That two chapters of one series are two rows, and a written-down sentinel is repaired.
 *
 * A keyed list refuses two rows with one key. Two chapters of one series that the server
 * gave neither a title nor a number read alike, so both used to key on `CHAPTER:<series>:`
 * and the search screen threw. iOS's `HitIdentityTests` asserts the same table.
 */
class HitIdentityTest {

    private fun chapterHit(chapterId: Int, title: String = "") =
        KavitaHit(KavitaHit.Kind.CHAPTER, title, seriesId = 7, chapterId = chapterId)

    @Test
    fun `two nameless chapters of one series are two rows`() {
        assertNotEquals(chapterHit(1).id, chapterHit(2).id)
    }

    @Test
    fun `one chapter found twice is still one row`() {
        assertEquals(chapterHit(1).id, chapterHit(1).id)
    }

    @Test
    fun `a series found by name and through a chapter is still one row`() {
        // The fold this identity was written for, and it still folds: a series hit carries
        // no chapter, so nothing finer was added to it.
        val byName = KavitaHit(KavitaHit.Kind.SERIES, "Green Lantern", seriesId = 7)
        val throughChapter = KavitaHit(KavitaHit.Kind.SERIES, "Green Lantern", seriesId = 7)
        assertEquals(byName.id, throughChapter.id)
    }

    private fun card(chapterName: String) = KavitaCard(
        publicationId = "p1",
        sourceId = "s1",
        seriesId = 7,
        chapterId = 3,
        chapterName = chapterName,
    )

    @Test
    fun `a card written before the guard is repaired when it is read`() {
        // Nothing rewrites a card, so the repair has to happen where it is read.
        assertNull(card("-100000").properChapterName)
        assertNull(card("100000").properChapterName)
        assertNull(card("   ").properChapterName)
        assertEquals("Year One", card("Year One").properChapterName)
    }

    @Test
    fun `a repaired card lets the file's own title through`() {
        val fromTheFile = Publication(
            identity = PublicationIdentity(normalizedPath = "/books/one.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "Batman: Year One",
            origin = MetadataOrigin.EMBEDDED,
        )
        assertEquals(
            "Batman: Year One",
            card("-100000").appliedTo(fromTheFile).displayTitle,
        )
    }
}
