package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
import app.storyarc.core.model.RememberedShelf

/**
 * One of the home surface's two shelves of shelves.
 *
 * `collections-and-reading-lists`, *Shelves on the home surface*. Absent when its half holds
 * nothing, by the rule [shelf] already follows for a run of covers -- a heading over a gap is
 * the surface looking like it is waiting for something, which is the one thing it must never
 * do.
 *
 * **The heading leads to the shelves screen, not to a filtered library.** Every other heading
 * here leads to "the full list in the library, filtered to match the shelf", and a collection
 * is not a library filter: the exhaustive list of collections is a screen of its own, which is
 * also the only place a shelf is made, renamed or deleted. [pinnedShelves] makes the same
 * argument from the other side, where the shelf is a collection's *contents*.
 *
 * iOS's `homeShelvesSection` is the same shelf.
 */
internal fun LazyListScope.homeShelvesShelf(
    heading: Int,
    summaries: List<HomeShelfSummary>,
    cover: suspend (Publication, Int) -> Bitmap?,
    serverArtwork: suspend (RememberedShelf) -> HomeShelfArtworkOutcome,
    onOpenShelf: (HomeShelfSummary) -> Unit,
    onShowAll: () -> Unit,
) {
    if (summaries.isEmpty()) return
    item(key = "shelves-heading-$heading") { HomeHeading(heading, onShowAll) }
    item(key = "shelves-run-$heading") {
        HomeShelfRun(summaries = summaries, cover = cover, serverArtwork = serverArtwork, onOpenShelf = onOpenShelf)
    }
}

/** A run of shelves at the width four covers still read as four. */
@Composable
private fun HomeShelfRun(
    summaries: List<HomeShelfSummary>,
    cover: suspend (Publication, Int) -> Bitmap?,
    serverArtwork: suspend (RememberedShelf) -> HomeShelfArtworkOutcome,
    onOpenShelf: (HomeShelfSummary) -> Unit,
) {
    // The shelves screen's own floor, not a cover cell's: a shelf is a composite of four
    // covers, and four covers below about 150 dp stop being four covers. Stepped for the text
    // size by the same ladder, because the caption under a shelf cramps the same way.
    val width = shelfLatticeMinimumWidth(LocalDensity.current.fontScale)
    LazyRow(
        contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.rowCoverGap),
        modifier = Modifier.fillMaxWidth(),
    ) {
        items(summaries, key = { it.key }) { summary ->
            HomeShelfLink(
                summary = summary,
                cover = cover,
                serverArtwork = serverArtwork,
                width = width,
                modifier = Modifier
                    .width(width)
                    .clickable { onOpenShelf(summary) },
            )
        }
    }
}

/**
 * One shelf on the home surface: its artwork, then its name, then what it is.
 *
 * The same three parts, in the same order, as the shelves screen's `ShelfCard`, and drawing
 * them here rather than calling that card is one divergence with a reason: `ShelfCard` resolves
 * its own artwork through a [LibraryViewModel], and the home surface deliberately holds no view
 * model -- `HomeScreen`'s signature is its promise that the surface is assembled from local
 * data it was handed. What is *not* duplicated is everything that decides how a shelf looks:
 * [ShelfComposite] lays out the quadrants and [ShelfProgressRail] draws the rail, for both.
 */
@Composable
private fun HomeShelfLink(
    summary: HomeShelfSummary,
    cover: suspend (Publication, Int) -> Bitmap?,
    serverArtwork: suspend (RememberedShelf) -> HomeShelfArtworkOutcome,
    width: Dp,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    // What the card's own fetch counted, drawn at once. The record keeps it for the next launch.
    var counted by remember(summary.key) { mutableStateOf<RememberedShelf?>(null) }
    val shown = counted?.let { summary.copy(count = it.count, finished = it.finished) } ?: summary
    val caption = homeShelfCaption(shown)

    Column(
        modifier = modifier.clearAndSetSemantics {
            contentDescription = listOf(summary.name, caption).filter { it.isNotEmpty() }
                .joinToString(", ")
        },
    ) {
        Box {
            HomeShelfArtwork(
                summary = summary,
                cover = cover,
                serverArtwork = serverArtwork,
                width = width,
                onCounted = { counted = it },
            )
            shown.fraction?.let { ShelfProgressRail(it) }
        }
        Column(modifier = Modifier.padding(top = StoryArcSpace.sm)) {
            Text(
                text = summary.name,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (caption.isNotEmpty()) {
                Text(
                    text = caption,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/**
 * A shelf's artwork, resolved through the home surface's own cover loader.
 *
 * [ShelfComposite] decides what the frame holds; this only fetches. A shelf the reader made
 * has local members, and its tiles are already the publications to ask the library's own
 * `cover` for -- the same request the library shelf and the list already make.
 *
 * **A shelf a server defined is the other branch, and it used to be the only one this
 * function had.** The owner's field report on v0.1.1: those cards showed a title and nothing
 * else, because [HomeShelfSummary.tiles] is always empty for one -- `home-screen` forbids
 * this surface from reaching a source on its own, so nothing had ever asked. [serverArtwork]
 * is the one door left open for exactly this: supplied by the app layer, which already knows
 * a source exists (see `HomeDestination`), so this composable still never builds a client
 * itself.
 */
@Composable
private fun HomeShelfArtwork(
    summary: HomeShelfSummary,
    cover: suspend (Publication, Int) -> Bitmap?,
    serverArtwork: suspend (RememberedShelf) -> HomeShelfArtworkOutcome,
    width: Dp,
    onCounted: (RememberedShelf) -> Unit,
) {
    val density = LocalDensity.current
    val maxPixelSize = remember(density, width) { with(density) { width.roundToPx() } }
    val covers = remember { mutableStateMapOf<String, Bitmap>() }
    val serverShelf = (summary.destination as? HomeShelfDestination.OnServer)?.shelf

    if (serverShelf != null && summary.tiles.isEmpty()) {
        // Keyed by the shelf, not by its cached count, so a new count does not fetch again.
        var plan by remember(serverShelf.key) { mutableStateOf<HomeShelfCoverPlan>(HomeShelfCoverPlan.Blank) }
        LaunchedEffect(serverShelf.key) {
            val outcome = serverArtwork(serverShelf)
            covers.putAll(outcome.covers)
            plan = outcome.plan
            outcome.counted?.let(onCounted)
        }
        val tiles = when (val resolved = plan) {
            is HomeShelfCoverPlan.Sole -> listOf(HOME_SHELF_SOLE_COVER_KEY)
            is HomeShelfCoverPlan.Composite -> resolved.ids
            HomeShelfCoverPlan.Blank -> emptyList()
        }
        ShelfComposite(tiles = tiles, covers = covers, name = summary.name)
    } else {
        LaunchedEffect(summary.tiles) {
            for (publication in summary.tiles) {
                if (covers.containsKey(publication.id)) continue
                cover(publication, maxPixelSize)?.let { covers[publication.id] = it }
            }
        }
        ShelfComposite(tiles = summary.tiles.map { it.id }, covers = covers, name = summary.name)
    }
}

/**
 * What a card says under its name: where the shelf came from, and how much is in it.
 *
 * The shelves screen's caption, asked the same way. A remembered shelf has no count this
 * device can vouch for, so it states its source alone rather than a zero -- and a shelf the
 * reader made here has no source, so it states the count alone.
 */
@Composable
private fun homeShelfCaption(summary: HomeShelfSummary): String {
    val items = summary.count?.let { pluralStringResource(R.plurals.shelves_count, it, it) }
    return listOfNotNull(summary.sourceName, items).joinToString(" · ")
}
