package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What the shelf draws once the reader has chosen between series and issues.
 *
 * `library-browsing`'s *A shelf of issues* scenario: "every publication is one cell, the ones
 * a series held included, and no cell stands for a group". The rule is one term on a gate
 * [rememberShelfRows] already had, and the gate is a composable — so this composes it rather
 * than reading it. iOS makes the same three exceptions in `LibraryView.rows`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ShelfRowsGroupingTest {

    @get:Rule
    val compose = createComposeRule()

    private fun issue(title: String, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.EMBEDDED,
    )

    private val shelf = listOf(
        issue("a", "Lantern"),
        issue("b", "Lantern"),
        issue("c", "Lantern"),
        issue("standalone"),
    )

    private fun rowsFor(
        grouping: LibraryGrouping,
        isGrouped: Boolean = false,
        isPicking: Boolean = false,
    ): ShelfRows {
        lateinit var rows: ShelfRows
        compose.setContent {
            rows = rememberShelfRows(shelf, isGrouped, isPicking, grouping)
        }
        compose.waitForIdle()
        return rows
    }

    @Test
    fun `the series grouping collapses a series into one cell`() {
        val rows = rowsFor(LibraryGrouping.SERIES)

        assertEquals(listOf("a", "standalone"), rows.shelved.map { it.displayTitle })
        assertEquals(3, rows.series.getValue(shelf[0].id).count)
    }

    @Test
    fun `the issues grouping lists every publication, and no cell stands for a group`() {
        val rows = rowsFor(LibraryGrouping.ISSUES)

        assertEquals(listOf("a", "b", "c", "standalone"), rows.shelved.map { it.displayTitle })
        assertTrue("a cell still stands for a series", rows.series.isEmpty())
    }

    /**
     * The two exceptions that were already here keep working under either choice: results are
     * grouped by why they matched, and a cell that opened a list mid-selection would throw
     * away what the reader had picked.
     */
    @Test
    fun `a search and a selection list issues whatever the reader chose`() {
        // One composition for all four combinations: a rule may set content only once, and
        // each of these is one call to the same gate rather than a screen of its own.
        val answers = mutableListOf<ShelfRows>()
        compose.setContent {
            for (grouping in LibraryGrouping.entries) {
                answers += rememberShelfRows(shelf, isGrouped = true, isPicking = false, grouping)
                answers += rememberShelfRows(shelf, isGrouped = false, isPicking = true, grouping)
            }
        }
        compose.waitForIdle()

        assertEquals(4, answers.size)
        for (rows in answers) {
            assertTrue("a cell stands for a series while searching or picking", rows.series.isEmpty())
            assertEquals(shelf.size, rows.shelved.size)
        }
    }
}
