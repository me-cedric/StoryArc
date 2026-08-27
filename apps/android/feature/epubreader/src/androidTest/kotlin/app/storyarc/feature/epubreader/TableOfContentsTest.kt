package app.storyarc.feature.epubreader

import org.junit.Assert.assertEquals
import org.junit.Test
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.util.Url

/**
 * Which navigation entry owns the reader's place, and when none of them does.
 *
 * The second half is the one worth a test. A publication whose whole text is one content
 * document lists every chapter as an anchor in that document, and matching on the resource
 * alone then marks the first chapter wherever the reader actually is. iOS's
 * `currentEntry(in:)` applies the same rule.
 *
 * Instrumented rather than a JVM unit test, and not by choice: Readium's `Url` is built on
 * `android.net.Uri`, which the unit-test android.jar stubs. Every assertion here threw
 * before the file moved, and turning `isReturnDefaultValues` on would have made the stubs
 * answer with defaults — which is to say the comparison under test would always agree.
 *
 * The method names are camelCase rather than backticked sentences for the same reason: an
 * instrumented test is dexed, and dex refuses a method name holding a space or a comma.
 */
class TableOfContentsTest {

    private fun entries(vararg hrefs: String): List<ContentsEntry> =
        hrefs.map { ContentsEntry(Link(href = Url(it)!!), depth = 0) }

    @Test
    fun anEntryPointingAtTheWholeResourceOwnsIt() {
        val rows = entries("OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml")

        assertEquals(1, rows.indexOfResource(Url("OEBPS/ch2.xhtml")))
    }

    @Test
    fun aResourceTheNavigationNeverNamesMarksNothing() {
        val rows = entries("OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml")

        assertEquals(-1, rows.indexOfResource(Url("OEBPS/afterword.xhtml")))
    }

    @Test
    fun aSingleDocumentBookMarksNothingRatherThanItsFirstChapter() {
        // Every entry is an anchor in one file. Nothing in a locator says which anchor the
        // reader has scrolled past, so a mark here would be wrong everywhere — and a mark
        // that is wrong everywhere is worse than none, because nobody can tell which it is.
        val rows = entries("book.xhtml#ch1", "book.xhtml#ch2", "book.xhtml#ch3")

        assertEquals(-1, rows.indexOfResource(Url("book.xhtml")))
    }

    @Test
    fun aNullResourceMarksNothing() {
        assertEquals(-1, entries("OEBPS/ch1.xhtml").indexOfResource(null))
    }

    @Test
    fun theTreeFlattensDepthFirstSoASectionFollowsItsOwnChapter() {
        val toc = listOf(
            Link(
                href = Url("OEBPS/ch1.xhtml")!!,
                title = "One",
                children = listOf(Link(href = Url("OEBPS/ch1.xhtml#a")!!, title = "One point one")),
            ),
            Link(href = Url("OEBPS/ch2.xhtml")!!, title = "Two"),
        )

        val rows = toc.flattenedEntries()

        assertEquals(listOf("One", "One point one", "Two"), rows.map { it.link.title })
        assertEquals(listOf(0, 1, 0), rows.map { it.depth })
    }
}
