package app.storyarc

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Search
import androidx.compose.ui.test.junit4.v2.createComposeRule
import app.storyarc.core.designsystem.navigation.AdaptiveNavigationShell
import app.storyarc.core.designsystem.navigation.CompactPlayerBar
import app.storyarc.core.designsystem.navigation.CompactPlayerLabels
import app.storyarc.core.designsystem.navigation.NavigationEntry
import app.storyarc.core.designsystem.navigation.RailMenuLabels
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Fixtures
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import app.storyarc.feature.library.HomeEntry
import app.storyarc.feature.library.HomeScreen
import app.storyarc.feature.library.HomeSurface
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 8: the compact player bar, resting above the navigation bar, over Home.
 *
 * The shell is the real one and the bar is the one the app shell draws, with the chapter and the
 * progress line an audiobook mid-chapter gives it.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue08CompactPlayerBarTest {

    @get:Rule
    val compose = createComposeRule()

    private val entries = listOf(
        NavigationEntry("Home", Icons.Filled.Home, selected = true) {},
        NavigationEntry("Library", Icons.Filled.Inventory2, selected = false) {},
        NavigationEntry("Search", Icons.Filled.Search, selected = false) {},
    )

    private val surface = HomeSurface(
        upNext = listOf("Tin Kingdom", "The Long Tide", "Paper Moons")
            .map { HomeEntry(Fixtures.publication(it), isReadableNow = true, pagesRemaining = null, fraction = 0.0) },
    )

    private fun draw(look: Look) = compose.catalogue("08-compact-player-bar", look) {
        AdaptiveNavigationShell(
            entries = entries,
            menu = RailMenuLabels(expand = "Expand", collapse = "Collapse"),
            aboveNavigation = {
                CompactPlayerBar(
                    title = "Sea Room",
                    chapter = "The Crossing",
                    isPlaying = true,
                    progress = 0.26f,
                    labels = CompactPlayerLabels(play = "Play", pause = "Pause", open = "Open player"),
                    onToggle = {},
                    onOpen = {},
                )
            },
        ) {
            HomeScreen(
                surface = surface,
                cover = { publication, _ -> Fixtures.cover(publication.displayTitle.length) },
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
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)

    @Test
    fun largest() = draw(Look.Largest)
}
