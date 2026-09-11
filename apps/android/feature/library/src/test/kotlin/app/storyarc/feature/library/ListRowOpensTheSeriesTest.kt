package app.storyarc.feature.library

import android.app.Application
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A row standing for a series opens the series, in the compact list as in the grid.
 *
 * `library-browsing`'s *Opening a series* scenario already required this, and the list could
 * not do it: it was handed the collapsed rows and knew nothing about series, so a row standing
 * for *Lantern* opened issue #1 and the other nineteen were unreachable in that layout. The
 * amended *A series is one row* scenario now says the two layouts answer the same way.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ListRowOpensTheSeriesTest {

    @get:Rule
    val compose = createComposeRule()

    private val viewModel by lazy {
        LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
    }

    private fun issue(title: String, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.EMBEDDED,
    )

    @Test
    fun `the series row opens the series, and a standalone row opens its page`() {
        val members = listOf(issue("Lantern #1", "Lantern"), issue("Lantern #2", "Lantern"))
        val standalone = issue("Harbour Lights")
        val rows = LibraryRows.of(members + standalone)
        val shelved = rows.map { it.lead }
        val series = rows.filterIsInstance<LibraryRow.Series>().associateBy { it.lead.id }

        val opened = mutableListOf<String>()
        val openedSeries = mutableListOf<String>()
        compose.setContent {
            StoryArcTheme {
                CoverList(
                    publications = shelved,
                    viewModel = viewModel,
                    onOpen = { opened += it.displayTitle },
                    seriesRows = series,
                    onOpenSeries = { openedSeries += it.name },
                )
            }
        }

        // The row is titled for the series, not for the issue leading it.
        compose.onNodeWithText("Lantern").performClick()
        assertEquals(listOf("Lantern"), openedSeries)
        assertEquals(emptyList<String>(), opened)

        compose.onNodeWithText("Harbour Lights").performClick()
        assertEquals(listOf("Harbour Lights"), opened)
        assertEquals(listOf("Lantern"), openedSeries)
    }
}
