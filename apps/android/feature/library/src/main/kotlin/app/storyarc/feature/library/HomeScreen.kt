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
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MediumFlexibleTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.carousel.HorizontalMultiBrowseCarousel
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
    onOpen: (Publication) -> Unit,
    onShowAll: (HomeSection) -> Unit,
    onOpenFile: () -> Unit,
    onAddFolder: () -> Unit,
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
                bottom = padding.calculateBottomPadding() + StoryArcSpace.xxl,
            ),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.section),
        ) {
            if (surface.isBare) {
                item { HomeFirstRun(onOpenFile = onOpenFile, onAddFolder = onAddFolder) }
                return@LazyColumn
            }

            keepReading(surface, cover, onOpen, onShowAll)

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
                width = homeHeroWidth(),
                modifier = Modifier
                    .padding(horizontal = StoryArcSpace.gutter)
                    .clickable { onOpen(entry.publication) }
                    .homeCardSemantics(entry, label),
            )
        }
        return
    }

    item {
        val width = homeHeroWidth()
        val state = rememberCarouselState { surface.keepReading.size }
        HorizontalMultiBrowseCarousel(
            state = state,
            preferredItemWidth = width,
            itemSpacing = StoryArcSpace.md,
            contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
            modifier = Modifier
                .fillMaxWidth()
                .height(
                    (width - StoryArcSpace.md * 2) * HOME_COVER_ASPECT +
                        homeCaptionHeight(lines = 5) + StoryArcSpace.xxl,
                ),
        ) { index ->
            val entry = surface.keepReading[index]
            val label = homeRemainingText(entry)
            HomeKeepReadingCard(
                entry = entry,
                cover = cover,
                width = width,
                modifier = Modifier
                    .maskClip(RoundedCornerShape(StoryArcRadius.xl))
                    .clickable { onOpen(entry.publication) }
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
private fun HomeHeading(text: Int, onShowAll: () -> Unit) {
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
    val width = coverMinimumWidth(homeWindowWidthDp()) * SHELF_COVER_SCALE
    LazyRow(
        contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.coverGap),
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
 * The first thing a reader ever sees, and the whole of it.
 *
 * `sources`: one sentence in plain language, one primary action that opens a comic from
 * the device with nothing to configure first, and one plain secondary that leads to
 * connecting a library — where, and only where, the four kinds of place are named. Nothing
 * here is a list of protocols to be understood before the app can be used.
 *
 * Hand-composed, per the divergence register #12: Material has no empty-state component,
 * and a port of iOS's would be the cross-platform habit this revamp is undoing. The *words*
 * are shared with iOS and with the library's own empty state, which is the same situation on
 * the next destination along: `library_empty_title` and `library_empty_subtitle` were two
 * near-identical pairs, differing by a word in French and a clause in English, which is how
 * one situation described twice in a four-language app comes apart.
 *
 * The secondary is a folder, not a menu of four. It is the one kind that needs no address
 * and no credentials, so it is the only one that can be finished in a single tap from a
 * screen a reader reached ten seconds after installing. The other three are named in the
 * library's own empty state, one destination along, where the reader is already looking for
 * somewhere to read from.
 */
@Composable
private fun HomeFirstRun(onOpenFile: () -> Unit, onAddFolder: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xxl),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.library_empty_title),
            style = MaterialTheme.typography.headlineSmall,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.library_empty_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
            modifier = Modifier
                .widthIn(max = 520.dp)
                .padding(bottom = StoryArcSpace.sm),
        )
        Button(onClick = onOpenFile) { Text(stringResource(R.string.library_open_comic)) }
        TextButton(onClick = onAddFolder) {
            Text(stringResource(R.string.library_add_folder))
        }
    }
}

/**
 * How wide the hero card is drawn.
 *
 * Wide enough that the cover is a cover and not a thumbnail, and never wider than half a
 * phone's screen — beyond that the carousel has nothing left to show beside it and stops
 * being a carousel. The two thresholds are Material's own medium and expanded breakpoints,
 * the same ones the cover grid uses.
 */
@Composable
private fun homeHeroWidth(): Dp = when {
    homeWindowWidthDp() >= 840 -> 280.dp
    homeWindowWidthDp() >= 600 -> 240.dp
    else -> 200.dp
}

/**
 * How much room the window has, in dp.
 *
 * From [LocalWindowInfo] rather than the configuration, for the reason `WindowClass.kt`
 * sets out: a multi-window slot, a rotation and a fold are all the same event, and the
 * container size is the only input that reports all three.
 */
@Composable
private fun homeWindowWidthDp(): Int {
    val density = LocalDensity.current
    val size = LocalWindowInfo.current.containerSize
    return with(density) { size.width.toDp() }.value.toInt()
}

/**
 * How much bigger a home shelf's covers are than the library grid's floor.
 *
 * The grid's number is a *minimum* for a wall of covers; a shelf shows six, so it can
 * afford them at the size the artwork was drawn to be seen at. "Artwork is the interface"
 * is not true of a 104 dp thumbnail.
 */
private const val SHELF_COVER_SCALE = 1.25f
