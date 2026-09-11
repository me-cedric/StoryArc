package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MediumFlexibleTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.carousel.HorizontalUncontainedCarousel
import androidx.compose.material3.carousel.rememberCarouselState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.grid.coverMinimumWidth
import app.storyarc.core.designsystem.grid.steppedForFontScale
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * A shelf on the home surface, named so its heading can lead somewhere exhaustive.
 *
 * `home-screen`: "no shelf silently truncates without offering the rest" — the heading
 * leads to the library "filtered to match the shelf". Which filter that is belongs to the
 * app layer, which owns the library's query; this only says which shelf was chosen.
 */
enum class HomeSection { KEEP_READING, UP_NEXT, RECENTLY_ADDED, FINISHED }

/**
 * The reading room.
 *
 * Assembled entirely from [HomeSurface], which is built from local reading history — so
 * this composable has nothing to wait for, no loading state to draw, and no way to grow a
 * shelf once a server answers. That is `home-screen`'s central requirement expressed as a
 * signature rather than as a promise.
 *
 * **This is Material's answer to the screen, not iOS's.** The register in the design
 * direction §4.9 lists every deliberate divergence; three of them land here. #9: the type
 * comes from Material's scale, not StoryArc's, because a type scale is a platform artifact
 * and these are Material slots. #10: the hero is emphasised by shape break and containment
 * rather than by a prominent button, which also means no colour is put on anyone's
 * artwork. #12: the empty state is hand-composed, because Material publishes no
 * `ContentUnavailableView` and porting one would be exactly the failure this revamp exists
 * to avoid.
 *
 * The surface degrades by changing shape, never by drawing an empty container: a section
 * with nothing in it is not drawn, one thing in progress is a single card rather than a
 * carousel of one, and a library with nothing at all in it *is* the first-run screen.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    surface: HomeSurface,
    cover: suspend (Publication, Int) -> Bitmap?,
    /**
     * A cover was chosen: that publication's page.
     *
     * `publication-detail` requires a page behind every cover and requires it to be
     * distinguished from resuming. Up next, recently added and finished are shelves of
     * covers, so they lead here.
     */
    onOpen: (Publication) -> Unit,
    /**
     * Keep reading was chosen: the book itself, at the recorded position.
     *
     * The hero is a resume affordance and the delta says so in as many words — chosen from
     * Keep reading, "the book opens at the recorded position, without this page in
     * between". `home-screen` asks for the same thing from the other side: straight into
     * the reader "with no intermediate screen".
     */
    onResume: (Publication) -> Unit,
    /**
     * Keep reading's card offered to finish the book, and the reader took it.
     *
     * `home-screen`, *A publication with nothing meaningful left*: "choosing to finish it
     * removes it from Keep reading by the same rule that finishing normally does" — so the
     * caller marks it read, and this shelf recomputes from the record. There is no second
     * rule for leaving this row, which is what makes the two ways of finishing one way.
     */
    onFinish: (Publication) -> Unit,
    onShowAll: (HomeSection) -> Unit,
    onOpenFile: () -> Unit,
    onAddFolder: () -> Unit,
    /**
     * The three source kinds that need an address before they hold anything.
     *
     * Here because the first-run state is now [EmptyLibrary], which names all four kinds.
     * A first launch lands on this surface, so this is the only surface that reader sees.
     */
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
    /**
     * The reader's own collections and reading lists, as two shelves.
     *
     * A second pure value beside [surface] rather than a field inside it, because it answers a
     * different question: [surface] is assembled from reading *history*, and this is assembled
     * from *curation* -- a collection the reader made and a shelf a server once named. Both are
     * local, which is the property `home-screen` insists on; neither waits for anything.
     *
     * Empty by default, so a preview and a test that does not care about shelves is unchanged.
     */
    shelves: HomeShelfListing = HomeShelfListing(),
    /** A shelf's card was chosen: that shelf's own screen, local or on its server. */
    onOpenShelf: (HomeShelfSummary) -> Unit = {},
    /** Either shelves heading was chosen: the screen that lists every collection and list. */
    onShowAllShelves: () -> Unit = {},
) {
    val palette = LocalStoryArcPalette.current
    // The flexible bar, not the small one all twelve of the app's other bars use. Its large
    // title is the editorial register the direction asks of a discovery surface, and it
    // collapses out of the way as the reader descends into the artwork.
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = palette.surfaceCanvas,
        topBar = {
            MediumFlexibleTopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.home_title),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = palette.surfaceCanvas,
                    scrolledContainerColor = palette.surfaceRaised,
                    titleContentColor = palette.textPrimary,
                ),
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = padding.calculateTopPadding(),
                // The extra `xxl` is breathing room under the last shelf, so the final cover
                // clears the navigation bar. The empty state is not a shelf: it centres itself
                // in whatever room it is given, so an extra bottom inset moves its middle up
                // and it stopped matching the library's, by half of `xxl`. Measured on a
                // OnePlus 7T Pro: the title sat 55 pixels higher than the library's.
                bottom = padding.calculateBottomPadding() +
                    if (surface.isBare) 0.dp else StoryArcSpace.xxl,
            ),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.section),
        ) {
            if (surface.isBare) {
                // The library's own empty state, drawn here rather than copied here.
                //
                // A first launch lands on home, not on the library, so the surface that "has
                // not yet asked the question the four kinds answer" is the only surface the
                // reader sees. A separate home state named two kinds and left a reader with a
                // Kavita server to guess that a second destination held what they came for.
                // Recorded in `one-library-three-destinations`, "Reversed on 2026-09-07".
                //
                // One composable rather than two, so the pair cannot drift apart again. iOS
                // deleted `HomeEmpty` and draws `EmptyLibraryView` for the same reason.
                item {
                    EmptyLibrary(
                        // `fillParentMaxSize`, not `fillMaxSize`: a `LazyColumn` item measures
                        // against unbounded height, so `fillMaxSize` collapses and the block
                        // lands at the top. That is how home and the library came to disagree.
                        modifier = Modifier.fillParentMaxSize(),
                        onOpenComic = onOpenFile,
                        onAddFolder = onAddFolder,
                        onAddCatalogue = onAddCatalogue,
                        onAddKavita = onAddKavita,
                        onAddShare = onAddShare,
                    )
                }
                return@LazyColumn
            }

            keepReading(surface, cover, onResume, onFinish, onOpen, onShowAll)

            shelf(
                entries = surface.upNext,
                heading = R.string.home_up_next,
                section = HomeSection.UP_NEXT,
                cover = cover,
                onOpen = onOpen,
                onShowAll = onShowAll,
            )

            shelf(
                entries = surface.recentlyAdded,
                heading = R.string.home_recently_added,
                section = HomeSection.RECENTLY_ADDED,
                cover = cover,
                onOpen = onOpen,
                onShowAll = onShowAll,
            )

            // The index before the expansions: these two name every shelf the reader has, and
            // the pinned ones below open the contents of a few of them. Above Finished, which
            // `home-screen` fixes as last on the surface.
            homeShelvesShelf(
                heading = R.string.shelves_collections,
                summaries = shelves.collections,
                cover = cover,
                onOpenShelf = onOpenShelf,
                onShowAll = onShowAllShelves,
            )

            homeShelvesShelf(
                heading = R.string.shelves_lists,
                summaries = shelves.lists,
                cover = cover,
                onOpenShelf = onOpenShelf,
                onShowAll = onShowAllShelves,
            )

            pinnedShelves(surface, cover, onOpen)

            finished(surface, cover, onOpen, onShowAll)
        }
    }
}

/**
 * Keep reading — the hero, and the only emphasised thing on the surface.
 *
 * Material's own carousel, which is the single most obvious component in an app of this
 * kind. `HorizontalMultiBrowseCarousel` shows one item at full size with the next ones
 * masked down beside it, so a reader sees at a glance both what they are in the middle of
 * and that there is more of it — which is what a row of equal cells cannot say.
 *
 * The carousel masks its items, and `design.md` forbids cropping artwork. Both hold here
 * because the thing being masked is the **card**, not the cover: the focused card shows its
 * cover whole, and what the mask trims at the edges is a container. A carousel of bare
 * covers would have been the cropping the tokens refuse.
 *
 * With one publication in progress there is no carousel at all — `home-screen` asks for a
 * single large card rather than a carousel of one, and a carousel with nothing to browse
 * carries every affordance of a thing that does.
 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
private fun LazyListScope.keepReading(
    surface: HomeSurface,
    cover: suspend (Publication, Int) -> Bitmap?,
    /** Opens the book. The hero is the surface's one resume affordance. */
    onResume: (Publication) -> Unit,
    /** Marks it read, for a book with a page or less left. */
    onFinish: (Publication) -> Unit,
    /** A cover's own page, for the next issue offered beside Finish. */
    onOpen: (Publication) -> Unit,
    onShowAll: (HomeSection) -> Unit,
) {
    if (surface.keepReading.isEmpty()) return

    item { HomeHeading(R.string.home_keep_reading) { onShowAll(HomeSection.KEEP_READING) } }

    if (surface.leadsWithOneCard) {
        item {
            val entry = surface.keepReading.single()
            val label = homeRemainingText(entry)
            HomeKeepReadingCard(
                entry = entry,
                cover = cover,
                width = homeHeroWidth(
                    homeWindowWidthDp(),
                    homeWindowHeightDp(),
                    LocalDensity.current.fontScale,
                ),
                onResume = { onResume(entry.publication) },
                onFinish = { onFinish(entry.publication) },
                onOpenNext = onOpen,
                modifier = Modifier
                    .padding(horizontal = StoryArcSpace.gutter)
                    .clickable { onResume(entry.publication) }
                    .homeCardSemantics(entry, label),
            )
        }
        return
    }

    item {
        val width = homeHeroWidth(
            homeWindowWidthDp(),
            homeWindowHeightDp(),
            LocalDensity.current.fontScale,
        )
        val state = rememberCarouselState { surface.keepReading.size }
        // A window with no room reports none for a frame or two, and a carousel handed a
        // card of no width throws rather than drawing nothing.
        if (width <= 0.dp) return@item
        // Uncontained, not multi-browse. A multi-browse carousel masks its items to
        // large, medium and small on purpose -- which is what it is for, and is not what
        // this row is: `home-screen` asks that "every card in the row has the same width
        // and the same height, whatever its title, its byline or its artwork". The reader
        // met three cards at three sizes and reported it as cards that are "not the same
        // size every time".
        HorizontalUncontainedCarousel(
            state = state,
            itemWidth = width,
            itemSpacing = StoryArcSpace.md,
            contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
            modifier = Modifier
                .fillMaxWidth()
                .height(homeHeroBlockHeight(width, LocalDensity.current.fontScale)),
        ) { index ->
            val entry = surface.keepReading[index]
            val label = homeRemainingText(entry)
            HomeKeepReadingCard(
                entry = entry,
                cover = cover,
                width = width,
                onResume = { onResume(entry.publication) },
                onFinish = { onFinish(entry.publication) },
                onOpenNext = onOpen,
                modifier = Modifier
                    .maskClip(RoundedCornerShape(StoryArcRadius.xl))
                    .clickable { onResume(entry.publication) }
                    .homeCardSemantics(entry, label),
            )
        }
    }
}

/** A plain shelf: a heading with a way through to the whole list, and a run of covers. */
private fun LazyListScope.shelf(
    entries: List<HomeEntry>,
    heading: Int,
    section: HomeSection,
    cover: suspend (Publication, Int) -> Bitmap?,
    onOpen: (Publication) -> Unit,
    onShowAll: (HomeSection) -> Unit,
) {
    if (entries.isEmpty()) return
    item { HomeHeading(heading) { onShowAll(section) } }
    item { HomeCoverRun(entries = entries, cover = cover, onOpen = onOpen) }
}

/**
 * The reader's pinned collections and reading lists, one shelf each.
 *
 * `home-screen`, *Pinned shelves*: a pinned shelf "appears on the home surface as a shelf of
 * its own", and *The rest of the home surface* puts them between recently added and finished.
 *
 * **No heading arrow, unlike every other shelf here.** `Every shelf leads somewhere
 * exhaustive` asks a heading to lead "to the full list in the library, filtered to match the
 * shelf" -- and a collection is not a library filter, it is a shelf with a screen of its own.
 * Sending the reader to a filtered library would show them a different set under the same
 * name. The way through is the shelf's own screen, one destination along, which is where they
 * pinned it from. Named here so the difference reads as a decision rather than an omission.
 *
 * `key` is the pin's token: stable across a rename, unique across the two kinds, and already
 * the string the choice is stored as.
 */
private fun LazyListScope.pinnedShelves(
    surface: HomeSurface,
    cover: suspend (Publication, Int) -> Bitmap?,
    onOpen: (Publication) -> Unit,
) {
    surface.pinned.forEach { shelf ->
        item(key = "pinned-${shelf.pin.token}") {
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                HomeShelfName(shelf.name)
                HomeCoverRun(entries = shelf.entries, cover = cover, onOpen = onOpen)
            }
        }
    }
}

/**
 * A heading that is the reader's own words rather than one of ours.
 *
 * The same size and weight as [HomeHeading] so a pinned shelf reads as a peer of the ones
 * around it, and without the arrow for the reason above.
 */
@Composable
private fun HomeShelfName(name: String) {
    Text(
        text = name,
        style = MaterialTheme.typography.titleLarge,
        color = LocalStoryArcPalette.current.textPrimary,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    )
}

/**
 * Finished, last on the surface and grouped by when.
 *
 * One heading for the section and a quiet label per period, rather than three headings of
 * equal weight: the reader is looking for *a book they finished*, and three top-level
 * headings would put three things of the same size in front of that one question.
 */
private fun LazyListScope.finished(
    surface: HomeSurface,
    cover: suspend (Publication, Int) -> Bitmap?,
    onOpen: (Publication) -> Unit,
    onShowAll: (HomeSection) -> Unit,
) {
    if (surface.finished.isEmpty()) return
    item { HomeHeading(R.string.home_finished) { onShowAll(HomeSection.FINISHED) } }
    surface.finished.forEach { group ->
        item(key = "finished-${group.period}") {
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                HomePeriodLabel(group.period)
                HomeCoverRun(entries = group.entries, cover = cover, onOpen = onOpen)
            }
        }
    }
}

/**
 * A section heading that leads somewhere exhaustive.
 *
 * `titleLarge` with a trailing arrow, which is Material's shape for this and not iOS's
 * chevron-in-a-navigation-link. The whole row is the target rather than the arrow alone —
 * a 24 dp glyph is not a touch target, and Material's minimum is 48.
 */
@Composable
internal fun HomeHeading(text: Int, onShowAll: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onShowAll)
            .heightIn(min = StoryArcSpace.xxxl)
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    ) {
        Text(
            text = stringResource(text),
            style = MaterialTheme.typography.titleLarge,
            color = palette.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.widthIn(max = 480.dp),
        )
        Spacer(Modifier.weight(1f))
        Icon(
            imageVector = Icons.AutoMirrored.Filled.ArrowForward,
            contentDescription = stringResource(R.string.home_show_all),
            tint = palette.textTertiary,
        )
    }
}

@Composable
private fun HomePeriodLabel(period: HomeFinishedPeriod) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(
            when (period) {
                HomeFinishedPeriod.THIS_WEEK -> R.string.home_finished_this_week
                HomeFinishedPeriod.THIS_MONTH -> R.string.home_finished_this_month
                HomeFinishedPeriod.EARLIER -> R.string.home_finished_earlier
            },
        ),
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = Modifier.padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    )
}

/** A run of covers at the size the window can afford. */
@Composable
private fun HomeCoverRun(
    entries: List<HomeEntry>,
    cover: suspend (Publication, Int) -> Bitmap?,
    onOpen: (Publication) -> Unit,
) {
    val width = homeShelfCoverWidth(homeWindowWidthDp(), LocalDensity.current.fontScale)
    LazyRow(
        contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.rowCoverGap),
        modifier = Modifier.fillMaxWidth(),
    ) {
        items(entries, key = { it.id }) { entry ->
            val label = homeRemainingText(entry)
            HomeShelfCell(
                entry = entry,
                cover = cover,
                width = width,
                modifier = Modifier
                    .clickable { onOpen(entry.publication) }
                    .homeCardSemantics(entry, label),
            )
        }
    }
}

/**
 * How wide the Keep reading card is drawn — the single card and each carousel item both.
 *
 * These three widths are the hero's own and no grid asks them: the hero is a *card* with a
 * cover inside its padding, not a cell in a lattice, so `design.md` §4's 104 / 132 / 158
 * floor is not the quantity. What it does share is the accessibility step — the same
 * [steppedForFontScale] the cover ladder takes, for the same reason. The card's text is laid
 * out across the card's width less [StoryArcSpace.md] on each side, so a hero pinned at 200 dp
 * gives its title and its pages-left line 176 dp at every text size, while the shelf below it
 * goes 130 → 182.5 dp at font scale 1.5. That was this function: it read only the window and
 * never the font scale, which is the same defect [homeShelfCoverWidth] was fixed for, one
 * section up the same screen.
 *
 * Capped at the room the card is actually given, which is the window less a gutter on each
 * side — the single card is laid out inside `padding(horizontal = gutter)` and the carousel
 * inside `contentPadding` of the same, so that is the constraint either way. Without the cap
 * the step overflows a small window: a 300 dp freeform slot has 260 dp of room and would be
 * handed a 280 dp card.
 *
 * The two width thresholds are Material's medium and expanded breakpoints, the same pair
 * [coverMinimumWidth] uses; taken from the window for the reason [homeWindowWidthDp] gives.
 *
 * Not `@Composable`, so the arithmetic can be asserted without a window — `HomeCoverWidthTest`
 * is the only reach a plain JVM suite has into what this screen draws.
 */
internal fun homeHeroWidth(
    windowWidthDp: Int,
    windowHeightDp: Int,
    fontScale: Float,
): Dp {
    val room = (windowWidthDp.dp - StoryArcSpace.gutter * 2).coerceAtLeast(0.dp)
    val tier = when {
        windowWidthDp >= 840 -> 280.dp
        windowWidthDp >= 600 -> 240.dp
        // A share of the window rather than a fixed 200 dp. `home-screen`: "about one and
        // a half cards fit across a phone, so the second is plainly a second and not a
        // thumbnail beside a hero". 200 dp put two and a half on a 411 dp phone, which is
        // where the reader met three cards at three sizes.
        else -> room / HERO_CARDS_ACROSS
    }
    // Whichever is smaller: the share the width offers, and the width whose card the
    // *height* can afford. Both halves of the same scenario have to hold at once — a card
    // one and a half across is the reader's request, and a next heading still on screen is
    // the requirement, and on a short phone they disagree. The height wins there, which is
    // the only order that keeps the surface legible: a reader can scroll to see a second
    // card and cannot scroll to discover that a surface continues.
    val affordable = heroWidthTheHeightAffords(windowHeightDp, fontScale)
    // A floor under the height's answer, because the height can afford a *negative* card.
    // A landscape phone has less room above the fold than the chrome and the next heading
    // want, and the inverse of a budget already overspent is a negative width -- which the
    // carousel takes as an item width and throws on, taking Home with it. Found by
    // rotating the phone: `IndexOutOfBoundsException: Index -1 out of bounds` from
    // `createKeylinesWithPivot`, on a build every unit test passed.
    //
    // 200 dp is the width this card had before the row was widened, so a window too short
    // for the rule gets the hero it used to have rather than none at all.
    return minOf(tier.steppedForFontScale(fontScale), room, maxOf(affordable, minOf(HERO_FLOOR, room)))
}

/** The narrowest hero worth drawing, and what a window too short for the rule falls back to. */
private val HERO_FLOOR = 200.dp

/**
 * The widest card whose block still leaves the next heading on screen.
 *
 * [homeHeroBlockHeight] inverted. The block is the artwork -- the card's width less its
 * padding, at [HOME_COVER_ASPECT] -- plus a caption budget, the container's bottom padding
 * and the resume row; so given the height that is going spare, this is the width that
 * exactly spends it.
 *
 * The chrome numbers are `HomeHeroHeightTest`'s, which is where they are explained and
 * where a change to either is caught.
 */
private fun heroWidthTheHeightAffords(windowHeightDp: Int, fontScale: Float): Dp {
    val forTheCard = (windowHeightDp - HOME_CHROME_DP - HOME_NEXT_HEADING_DP).dp
    val forTheArt = forTheCard - homeCaptionHeight(lines = 6, fontScale = fontScale) -
        StoryArcSpace.xxl - HOME_RESUME_ROW
    return forTheArt / HOME_COVER_ASPECT + StoryArcSpace.md * 2
}

/**
 * How many Keep reading cards fit across a phone.
 *
 * One and a half: enough of the second to say the row scrolls, not so much that the first
 * stops being the surface's one emphasis. `HomeCoverWidthTest` pins both ends of that.
 */
private const val HERO_CARDS_ACROSS = 1.5f

/**
 * What Home spends above and below the hero, in dp.
 *
 * The expanded top bar including its status-bar padding, the navigation bar including its
 * gesture inset, and the *Keep reading* heading with its air. `HomeHeroHeightTest` is where
 * each number comes from; it is repeated here rather than shared because the test asserting
 * against a constant the code reads would be asserting its own arithmetic.
 */
private const val HOME_CHROME_DP = 112 + 88 + 56

/** A section heading and the air above it, which is what has to stay on screen. */
private const val HOME_NEXT_HEADING_DP = 56

/**
 * How much room the window has, in dp.
 *
 * From [LocalWindowInfo] rather than the configuration, for the reason `WindowClass.kt`
 * sets out: a multi-window slot, a rotation and a fold are all the same event, and the
 * container size is the only input that reports all three.
 */
@Composable
internal fun homeWindowWidthDp(): Int {
    val density = LocalDensity.current
    val size = LocalWindowInfo.current.containerSize
    return with(density) { size.width.toDp() }.value.toInt()
}

/** The window's height in dp, for the half of the hero's size the width cannot decide. */
@Composable
internal fun homeWindowHeightDp(): Int {
    val density = LocalDensity.current
    val size = LocalWindowInfo.current.containerSize
    return with(density) { size.height.toDp() }.value.toInt()
}

/**
 * How wide a cover on a plain home shelf is drawn.
 *
 * The plain shelves, and only those: [HomeCoverRun] is the sole caller, and it draws Up next,
 * Recently added and each Finished period group. Keep reading is a card and asks
 * [homeHeroWidth].
 *
 * The grid's ladder, scaled — the same rule the library grid and the Downloads shelf ask, so
 * a reader who turns their text size up finds these runs reflowed too. They did not: this read
 * `coverMinimumWidth(homeWindowWidthDp())` and the font scale was an optional argument, so at
 * scale 1.5 the library grid on the next destination widened 104 → 146 dp and every run on
 * Home kept its ordinary width. The argument is no longer optional, which is why that cannot
 * come back.
 *
 * Not `@Composable`, so the arithmetic can be asserted without a window — `HomeCoverWidthTest`
 * is the only reach a plain JVM suite has into what this screen draws.
 */
internal fun homeShelfCoverWidth(windowWidthDp: Int, fontScale: Float): Dp =
    coverMinimumWidth(windowWidthDp, fontScale) * SHELF_COVER_SCALE

/**
 * How much bigger a home shelf's covers are than the library grid's floor.
 *
 * The grid's number is a *minimum* for a wall of covers; a shelf shows six, so it can
 * afford them at the size the artwork was drawn to be seen at. "Artwork is the interface"
 * is not true of a 104 dp thumbnail.
 */
private const val SHELF_COVER_SCALE = 1.25f
