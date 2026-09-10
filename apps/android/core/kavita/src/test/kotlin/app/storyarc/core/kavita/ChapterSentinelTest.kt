package app.storyarc.core.kavita

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * That Kavita's no-number sentinel never leaves the model as a number.
 *
 * **`-100000` is what Kavita writes for a chapter with no number at all** — a collected
 * edition, a volume with one part. A reader met it three times over: as a row in a chapter
 * list, as *Continue -100000*, and as the name a downloaded file was written under. Each
 * of those screens asked the question its own way, and the shelf had been guarded while
 * the others had not.
 *
 * So the rule lives here, on the model every screen reads, and this is the test that keeps
 * it there. iOS's `ChapterSentinelTests` asserts the same table against the same fields.
 */
class ChapterSentinelTest {

    private fun chapter(number: String, title: String? = null) =
        KavitaChapter(id = 1, number = number, title = title)

    @Test
    fun `a real number is a number`() {
        assertEquals("43", chapter("43").issueNumber)
        assertEquals("43", chapter("43").displayName)
    }

    @Test
    fun `a decimal chapter is a number too, because half issues exist`() {
        assertEquals("1.5", chapter("1.5").issueNumber)
    }

    @Test
    fun `the sentinel is not a number`() {
        assertNull(chapter("-100000").issueNumber)
    }

    @Test
    fun `any negative is not a number, because none of them is an issue`() {
        assertNull(chapter("-1").issueNumber)
        assertNull(chapter("-42").issueNumber)
    }

    @Test
    fun `nothing at all is not a number`() {
        assertNull(chapter("").issueNumber)
        assertNull(chapter("   ").issueNumber)
    }

    @Test
    fun `a title always wins, sentinel or not`() {
        assertEquals("The Long Halloween", chapter("-100000", "The Long Halloween").displayName)
        assertEquals("Issue 43", chapter("43", "Issue 43").displayName)
    }

    @Test
    fun `an unnumbered chapter has no name of its own, and does not invent one`() {
        // Empty rather than a made-up label: what to call it is the screen's decision, and
        // a screen has its own words for it — `chapterLabel` says *Unnumbered*, which is
        // true, where this used to say "-100000", which is a database's private business.
        assertEquals("", chapter("-100000").displayName)
        assertEquals("", chapter("-100000", "").displayName)
    }
}
