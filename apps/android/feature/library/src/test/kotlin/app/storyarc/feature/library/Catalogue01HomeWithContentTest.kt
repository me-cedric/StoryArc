package app.storyarc.feature.library

import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Catalogue entry 1: home with content. Keep reading, up next, recently added and finished. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue01HomeWithContentTest {

    @get:Rule
    val compose = createComposeRule()

    private val shelf = CatalogueShelf.publications

    private val surface = HomeSurface(
        keepReading = listOf(
            CatalogueShelf.entry(shelf[0], fraction = 0.42),
            CatalogueShelf.entry(shelf[1], fraction = 0.7),
        ),
        upNext = listOf(shelf[2], shelf[3], shelf[4]).map { CatalogueShelf.entry(it) },
        recentlyAdded = listOf(shelf[5], shelf[6], shelf[7]).map { CatalogueShelf.entry(it) },
        finished = listOf(
            HomeFinishedGroup(
                HomeFinishedPeriod.THIS_WEEK,
                listOf(shelf[8], shelf[9]).map { CatalogueShelf.entry(it, state = app.storyarc.core.model.ReadState.FINISHED) },
            ),
        ),
    )

    private fun draw(look: Look) = compose.catalogue("01-home-with-content", look) {
        HomeScreen(
            surface = surface,
            cover = { publication, _ -> CatalogueShelf.cover(publication) },
            onOpen = {},
            onResume = {},
            onFinish = {},
            onShowAll = {},
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
