package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.model.ReadState
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Fixtures
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Catalogue entry 14: the search page with nothing typed, three shelves of suggestions. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue14SearchAtRestTest {

    @get:Rule
    val compose = createComposeRule()

    private fun entry(seed: Int, title: String, fraction: Double = 0.0) = HomeEntry(
        publication = Fixtures.publication(title, authors = listOf("Fixture Author")),
        isReadableNow = true,
        pagesRemaining = if (fraction > 0.0) 24 else null,
        fraction = fraction,
        state = if (fraction > 0.0) ReadState.IN_PROGRESS else ReadState.UNREAD,
    )

    private fun draw(look: Look) = compose.catalogue("14-search-at-rest", look) {
        val suggestions = SearchSuggestions(
            inProgress = listOf(entry(0, "Harbour Lights", 0.4), entry(1, "Cinder Season", 0.7)),
            nextInSeries = listOf(entry(2, "Tin Kingdom")),
            neverOpened = listOf(entry(3, "The Long Tide"), entry(4, "Paper Moons")),
        )
        SearchAtRest(
            suggestions = suggestions,
            scope = LibraryAvailability.EVERYTHING,
            onScopeChange = {},
            cover = { publication, _ -> Fixtures.cover(publication.displayTitle.length) },
            onOpenPage = {},
            onOpenFile = {},
            onAddFolder = {},
            onAddCatalogue = {},
            onAddKavita = {},
            onAddShare = {},
        )
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
