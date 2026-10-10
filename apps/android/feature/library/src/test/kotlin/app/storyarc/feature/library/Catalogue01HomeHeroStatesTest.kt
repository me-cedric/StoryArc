package app.storyarc.feature.library

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.performScrollToNode
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.catalogue
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entries 1b to 1f: the states of the Home hero and of its shelves that entry 1 does
 * not draw. A card at the end of its book, a card whose source is away, Home after Finish, and
 * Home with a pinned collection and a pinned reading list.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue01HomeHeroStatesTest {

    @get:Rule
    val compose = createComposeRule()

    private val shelf = CatalogueShelf.publications

    private fun atTheEnd(next: Boolean) = CatalogueShelf.entry(shelf[0], fraction = 0.97, pagesRemaining = 1)
        .copy(isAtTheEnd = true, nextInSeries = if (next) shelf[6] else null)

    private val upNext = listOf(shelf[2], shelf[3], shelf[4]).map { CatalogueShelf.entry(it) }

    private fun draw(
        entry: String,
        look: Look,
        surface: HomeSurface,
        scrollTo: String? = null,
    ) = compose.catalogue(
        entry,
        look,
        act = { scrollTo?.let { onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasText(it)) } },
    ) {
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

    private val finishAndNext = HomeSurface(keepReading = listOf(atTheEnd(next = true)), upNext = upNext)

    private val finishAlone = HomeSurface(keepReading = listOf(atTheEnd(next = false)), upNext = upNext)

    private val sourceAway = HomeSurface(
        keepReading = listOf(CatalogueShelf.entry(shelf[0], fraction = 0.42).copy(isReadableNow = false)),
        upNext = upNext,
    )

    private val afterFinish = HomeSurface(
        upNext = upNext,
        finished = listOf(
            HomeFinishedGroup(
                HomeFinishedPeriod.THIS_WEEK,
                listOf(CatalogueShelf.entry(shelf[0], state = ReadState.FINISHED)),
            ),
        ),
    )

    private val pinned = HomeSurface(
        keepReading = listOf(CatalogueShelf.entry(shelf[1], fraction = 0.7)),
        recentlyAdded = listOf(shelf[5], shelf[6], shelf[7]).map { CatalogueShelf.entry(it) },
        pinned = listOf(
            HomePinnedShelf(
                ShelfPin.Collection(UUID(0, 1)),
                "Harbour stories",
                listOf(shelf[0], shelf[8], shelf[9]).map { CatalogueShelf.entry(it) },
            ),
            HomePinnedShelf(
                ShelfPin.ReadingListPin(UUID(0, 2)),
                "Read in this order",
                listOf(shelf[9], shelf[3], shelf[0]).map { CatalogueShelf.entry(it) },
            ),
        ),
    )

    @Test
    fun finishAndNextLight() = draw("01b-home-finish-and-next", Look.Light, finishAndNext)

    @Test
    fun finishAndNextDark() = draw("01b-home-finish-and-next", Look.Dark, finishAndNext)

    @Test
    fun finishAloneLight() = draw("01c-home-finish-alone", Look.Light, finishAlone)

    @Test
    fun finishAloneDark() = draw("01c-home-finish-alone", Look.Dark, finishAlone)

    @Test
    fun sourceAwayLight() = draw("01d-home-source-away", Look.Light, sourceAway)

    @Test
    fun sourceAwayDark() = draw("01d-home-source-away", Look.Dark, sourceAway)

    @Test
    fun afterFinishLight() = draw("01e-home-after-finish", Look.Light, afterFinish)

    @Test
    fun afterFinishDark() = draw("01e-home-after-finish", Look.Dark, afterFinish)

    @Test
    fun pinnedLight() = draw("01f-home-pinned-shelves", Look.Light, pinned, scrollTo = "Harbour stories")

    @Test
    fun pinnedDark() = draw("01f-home-pinned-shelves", Look.Dark, pinned, scrollTo = "Harbour stories")
}
