package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `library-browsing`: "when a reader opens a series, then its publications are listed in
 * their own order" -- the library's `SERIES` comparison (number, then natural filename), not
 * the order the library adopted them in.
 *
 * iOS's `SeriesShelfMembersTests` asserts the same cases.
 */
class SeriesShelfMembersTest {

    private fun publication(title: String, series: String, number: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/fixtures/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        number = number,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `a series opened out of adoption order is listed by issue number`() {
        val library = listOf(
            publication("Issue 10", series = "Nightjar", number = "10"),
            publication("Issue 2", series = "Nightjar", number = "2"),
            publication("Issue 1", series = "Nightjar", number = "1"),
        )
        assertEquals(
            listOf("Issue 1", "Issue 2", "Issue 10"),
            seriesShelfMembers("Nightjar", library).map { it.displayTitle },
        )
    }

    @Test
    fun `only that series' own members are listed`() {
        val library = listOf(
            publication("Nightjar #1", series = "Nightjar", number = "1"),
            publication("Ashfall #1", series = "Ashfall", number = "1"),
        )
        assertEquals(listOf("Nightjar #1"), seriesShelfMembers("Nightjar", library).map { it.displayTitle })
    }
}
