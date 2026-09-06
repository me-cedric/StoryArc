package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

/**
 * The fallback `local-library` names, asserted against the same table as iOS's
 * `FilenameOrderTests`.
 *
 * *Nested folder structure becomes series*: "a subfolder whose contents cannot be
 * ordered falls back to case-insensitive natural filename order". A folder of scans
 * whose embedded titles are absent or identical carries nothing else, so the filename
 * is the only thing left to order by. Add a case here, add it there.
 */
class FilenameOrderTest {

    private fun publication(
        title: String,
        series: String? = null,
        number: String? = null,
        file: String? = null,
    ) = Publication(
        identity = PublicationIdentity(normalizedPath = file?.let { "/library/Kagurabachi/$it" }),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        number = number,
        origin = MetadataOrigin.INFERRED,
    )

    private fun files(publications: List<Publication>) = publications.map {
        it.identity.normalizedPath.orEmpty().split('/').last { part -> part.isNotEmpty() }
    }

    @Test
    fun `a chapter ten follows a chapter two, because the digits compare as numbers`() {
        val library = listOf(
            publication("Chapter", series = "Kagurabachi", file = "ch10.cbz"),
            publication("Chapter", series = "Kagurabachi", file = "ch1.cbz"),
            publication("Chapter", series = "Kagurabachi", file = "ch2.cbz"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("ch1.cbz", "ch2.cbz", "ch10.cbz"), files(sorted))
    }

    @Test
    fun `case alone does not decide, so a capital chapter two still precedes chapter ten`() {
        val library = listOf(
            publication("Chapter", series = "Kagurabachi", file = "CH10.cbz"),
            publication("Chapter", series = "Kagurabachi", file = "Ch2.cbz"),
            publication("Chapter", series = "Kagurabachi", file = "ch1.cbz"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("ch1.cbz", "Ch2.cbz", "CH10.cbz"), files(sorted))
    }

    @Test
    fun `a numeral outside the ten digits orders as a character, so both platforms agree`() {
        val library = listOf(
            publication("Chapter", series = "Kagurabachi", file = "ch\u0663.cbz"),
            publication("Chapter", series = "Kagurabachi", file = "ch\u00B2.cbz"),
            publication("Chapter", series = "Kagurabachi", file = "cha.cbz"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("cha.cbz", "ch\u00B2.cbz", "ch\u0663.cbz"), files(sorted))
    }

    @Test
    fun `a series that carries issue numbers keeps them, and the filename never fires`() {
        val library = listOf(
            publication("Chapter", series = "Kagurabachi", number = "2", file = "z.cbz"),
            publication("Chapter", series = "Kagurabachi", number = "10", file = "a.cbz"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("z.cbz", "a.cbz"), files(sorted))
    }

    @Test
    fun `a title sort still files by the collated title, not by the filename`() {
        val library = listOf(
            publication("The Sandman", file = "a.cbz"),
            publication("Akira", file = "z.cbz"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.TITLE), Locale.ENGLISH)
        assertEquals(listOf("Akira", "The Sandman"), sorted.map { it.displayTitle })
    }

    @Test
    fun `a tie under any other sort files by the collated title, because the shelf is not a folder`() {
        val library = listOf(
            publication("Maus II", file = "Maus II.cbz"),
            publication("Maus", file = "Maus.cbz"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.YEAR), Locale.ENGLISH)
        assertEquals(listOf("Maus", "Maus II"), sorted.map { it.displayTitle })
    }

    @Test
    fun `a series of server chapters keeps the collated title, because a chapter has no filename`() {
        val library = listOf(
            publication("A Zoo", series = "Kagurabachi"),
            publication("Bee", series = "Kagurabachi"),
        )
        val sorted = LibraryIndex.arrange(library, LibraryQuery(sort = LibrarySort.SERIES), Locale.ENGLISH)
        assertEquals(listOf("Bee", "A Zoo"), sorted.map { it.displayTitle })
    }
}
