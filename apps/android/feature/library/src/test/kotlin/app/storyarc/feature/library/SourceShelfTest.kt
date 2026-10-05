package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What *more from this library* puts on the screen.
 *
 * `library-browsing`, *More from a source than the library holds*: the publications a source
 * holds beyond the first slice "are rendered by the same grid, the same cells and the same
 * publication page as everything else". The footer used to open the source's own browser,
 * which draws a catalogue with cells of its own, so these rows are the half of that clause a
 * JVM test can hold: one source's publications, in the library's own arrangement, collapsed
 * into the library's own rows.
 *
 * iOS's `SourceShelfTests` asserts the same four cases.
 */
class SourceShelfTest {

    private fun issue(title: String, from: UUID?, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.EMBEDDED,
        sourceId = from,
    )

    @Test
    fun `only the library that was asked for`() {
        val asked = UUID.randomUUID()
        val other = UUID.randomUUID()

        val shelf = sourceShelfMembers(asked, listOf(issue("mine", asked), issue("theirs", other)))

        assertEquals(listOf("mine"), shelf.map { it.displayTitle })
    }

    @Test
    fun `a publication no source claims belongs to no library's shelf`() {
        // [LibraryScope.contains] is the rule, and it is the library's own: a file another
        // app handed over came from somewhere the reader never configured, and attributing it
        // to whichever source is open would be a guess.
        val asked = UUID.randomUUID()

        assertTrue(sourceShelfMembers(asked, listOf(issue("dropped in", null))).isEmpty())
    }

    @Test
    fun `in the library's own arrangement, not the order the pages arrived in`() {
        // The later pages are adopted as they come back from the server, so adoption order is
        // the order one server answered in. The shelf's default is title, ascending.
        val asked = UUID.randomUUID()

        val shelf = sourceShelfMembers(asked, listOf(issue("Zephyr", asked), issue("Ashfall", asked)))

        assertEquals(listOf("Ashfall", "Zephyr"), shelf.map { it.displayTitle })
    }

    @Test
    fun `a series is one cell here too, because it is the library's own grid`() {
        val asked = UUID.randomUUID()

        val rows = LibraryRows.of(
            sourceShelfMembers(
                asked,
                listOf(
                    issue("Lantern 1", asked, series = "Lantern"),
                    issue("Lantern 2", asked, series = "Lantern"),
                    issue("Solo", asked),
                ),
            ),
        )

        assertEquals(2, rows.size)
        assertNotNull(rows.filterIsInstance<LibraryRow.Series>().singleOrNull())
    }
}
