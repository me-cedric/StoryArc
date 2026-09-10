package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * What the library lists when its publications belong to series.
 *
 * `library-browsing`: a series "is listed once, as a single cell", its issues "are not
 * listed beside it, whatever source they came from", and a publication with no series "is a
 * row of its own". Android's `LibraryRows` and iOS's twin answer the same cases.
 */
class LibraryRowsTest {

    private fun issue(title: String, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.EMBEDDED,
    )

    @Test
    fun `a series is one row, however many issues it holds`() {
        val rows = LibraryRows.of(
            listOf(issue("a", "Lantern"), issue("b", "Lantern"), issue("c", "Lantern")),
        )

        assertEquals(1, rows.size)
        assertEquals(3, (rows.single() as LibraryRow.Series).count)
    }

    @Test
    fun `a publication with no series is a row of its own`() {
        val rows = LibraryRows.of(listOf(issue("standalone")))

        assertEquals(listOf("standalone"), rows.map { it.lead.displayTitle })
        assertEquals(LibraryRow.One::class, rows.single()::class)
    }

    @Test
    fun `a series of one is not a series a reader has to open`() {
        // A row that opens a list holding one thing is a tap nobody needed to make.
        val rows = LibraryRows.of(listOf(issue("only", "Lantern")))

        assertEquals(LibraryRow.One::class, rows.single()::class)
    }

    @Test
    fun `a series takes the place its first member had`() {
        // The arrangement decided where the series belongs; gathering members from across
        // the shelf would undo the sort the reader chose.
        val rows = LibraryRows.of(
            listOf(
                issue("solo"),
                issue("a", "Lantern"),
                issue("later"),
                issue("b", "Lantern"),
            ),
        )

        // By what each row leads with, not by id: a lone publication's row id is the
        // publication's own, which says nothing about where the series landed.
        assertEquals(listOf("solo", "a", "later"), rows.map { it.lead.displayTitle })
        assertEquals(LibraryRow.Series::class, rows[1]::class)
    }

    @Test
    fun `a scattered series is still one row and keeps every member`() {
        val rows = LibraryRows.of(
            listOf(issue("a", "Lantern"), issue("x", "Titans"), issue("b", "Lantern")),
        )

        val lantern = rows.filterIsInstance<LibraryRow.Series>().single { it.name == "Lantern" }
        assertEquals(listOf("a", "b"), lantern.members.map { it.displayTitle })
        assertEquals(2, rows.size)
    }

    @Test
    fun `a blank series name is no series at all`() {
        val rows = LibraryRows.of(listOf(issue("a", ""), issue("b", " ")))

        assertEquals(2, rows.size)
        assertEquals(listOf(LibraryRow.One::class, LibraryRow.One::class), rows.map { it::class })
    }

    @Test
    fun `an empty library has no rows`() {
        assertEquals(emptyList<LibraryRow>(), LibraryRows.of(emptyList()))
    }
}
