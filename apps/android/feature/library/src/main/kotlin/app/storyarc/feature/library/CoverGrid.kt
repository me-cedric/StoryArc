package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.Publication

/**
 * The cover grid.
 *
 * `library-browsing`: "the number of grid columns follows the available width, and
 * cover size stays within the readable range defined in the design tokens".
 * [BoundedAdaptive] is what does that — a fixed column count would give a phone
 * postage stamps and a tablet a wall of enormous covers, and the platform's own
 * `GridCells.Adaptive` takes only the lower bound.
 *
 * iOS's `CoverGrid` uses the same two bounds for the same reason.
 */
@Composable
internal fun CoverGrid(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    /**
     * In-progress publications, most recently read first. Empty means the row is
     * not drawn — `library-browsing` requires it absent rather than shown empty.
     */
    continueReading: List<Publication> = emptyList(),
    /**
     * Search results under their own headings. Empty means there is no search running and
     * the shelf is drawn as one run of covers.
     */
    groups: List<MatchGroup> = emptyList(),
    /**
     * What to do when a cover is tapped. The library does not open the reader
     * itself — a feature module never depends on another feature module, so the
     * app layer wires the two together.
     */
    onOpen: (Publication) -> Unit,
    /** A long press, where a publication is put on a shelf. Nil where there is nowhere to put it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    /**
     * What the reader has picked, or null when they are not picking.
     *
     * `collections-and-reading-lists` wants publications "selected in bulk from the
     * library", and the library is a grid or a list depending on a control the reader
     * already owns -- so both of them take this, and neither is the one that works.
     */
    selection: Set<String>? = null,
    onToggle: (Publication) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    // The readable range. Below the minimum a cover stops being recognisable;
    // above the maximum a phone shows one and a half of them.
    val minimumWidth = 108.dp
    val maximumWidth = 168.dp
    val density = LocalDensity.current
    // Pixels, not dp: a cover decoded at dp size is blurry on every device made
    // since 2010.
    val maxPixelSize = remember(density) { with(density) { maximumWidth.roundToPx() } }

    val gridState = rememberLazyGridState()
    // The continue row arrives after the grid does — recorded positions are read
    // once the scan has something to match them against. A lazy grid anchors on
    // its first visible item, so inserting a row above that anchor leaves the new
    // row scrolled off the top of the screen rather than on it. Anchoring back to
    // the start is what makes it visible, and it only ever happens while the user
    // is still looking at the top of a freshly scanned library.
    LaunchedEffect(continueReading.isNotEmpty()) {
        if (continueReading.isNotEmpty()) gridState.scrollToItem(0)
    }

    LazyVerticalGrid(
        // Both bounds, not just the minimum: `GridCells.Adaptive` has no maximum, so a
        // narrow window stretched its single column to the full width and a cover filled
        // the screen. `BoundedAdaptive` is the other half of the scenario.
        columns = remember(minimumWidth, maximumWidth) {
            BoundedAdaptive(minimumWidth, maximumWidth)
        },
        state = gridState,
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = StoryArcSpace.gutter,
            vertical = StoryArcSpace.md,
        ),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
    ) {
        if (continueReading.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }, key = "continue-reading") {
                ContinueReadingRow(continueReading, viewModel, onOpen, maxPixelSize, onAddToShelf)
            }
        }
        // `library-browsing`: while a search is running, results are "grouped by match
        // kind". One heading and one run of covers per group rather than a second screen —
        // the reader is looking at their library with a word typed over it, not somewhere
        // else.
        val cell: @Composable (Publication) -> Unit = { publication ->
            CoverCell(
                publication,
                viewModel,
                onOpen,
                maxPixelSize,
                onAddToShelf,
                isPicked = selection?.contains(publication.id),
                onToggle = onToggle,
            )
        }
        if (groups.isEmpty()) {
            items(publications, key = { it.id }) { cell(it) }
        } else {
            for (group in groups) {
                item(span = { GridItemSpan(maxLineSpan) }, key = "heading-${group.kind}") {
                    MatchHeading(group.kind)
                }
                items(group.publications, key = { it.id }) { cell(it) }
            }
        }
    }
}

/**
 * Why the results under it matched.
 *
 * `library-browsing` asks for results "grouped by match kind — series, publication, person,
 * tag", which only means anything if the reader is told which group they are looking at.
 */
@Composable
internal fun MatchHeading(kind: MatchKind, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(kind.labelRes),
        style = MaterialTheme.typography.titleMedium,
        color = palette.textPrimary,
        modifier = modifier.fillMaxWidth().padding(top = StoryArcSpace.md),
    )
}

/**
 * How a match kind is named on screen.
 *
 * The kinds live in `:core:model` and carry no resources: the domain has no business
 * holding UI copy. Naming them is presentation, so it lives here — the same split iOS makes
 * with `titleKey`. Plural, because a heading names a set.
 */
private val MatchKind.labelRes: Int
    get() = when (this) {
        MatchKind.SERIES -> R.string.library_match_series
        MatchKind.PUBLICATION -> R.string.library_match_publication
        MatchKind.PERSON -> R.string.library_match_person
        MatchKind.TAG -> R.string.library_match_tag
    }

/**
 * What the reader was in the middle of.
 *
 * `library-browsing`: "a Continue reading row appears first, ordered by most
 * recently read". Horizontal, because it is a shortcut rather than a second
 * library — a vertical block of it would push the shelf off the screen.
 */
@Composable
private fun ContinueReadingRow(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    maxPixelSize: Int,
    /** A long press, where a publication is put on a shelf. Null where there is nowhere to put it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        Text(
            text = stringResource(R.string.library_continue_reading),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            items(publications, key = { it.id }) { publication ->
                CoverCell(
                    publication,
                    viewModel,
                    onOpen,
                    maxPixelSize,
                    // The same long press the shelf below answers. A publication does not
                    // stop having collections because it is the one you were last
                    // reading, and until this was passed through, the row was the only
                    // cover in the app whose long press did nothing.
                    onAddToShelf = onAddToShelf,
                    modifier = Modifier.width(128.dp),
                )
            }
        }
    }
}

/** One publication in the grid. */
@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun CoverCell(
    publication: Publication,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    maxPixelSize: Int,
    /** A long press, where a publication is put on a shelf. Null where there is nowhere to put it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    /** Whether this one is picked, or null when the library is not in selection mode. */
    isPicked: Boolean? = null,
    onToggle: (Publication) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, maxPixelSize)
    }

    val subtitle = cellSubtitle(publication)
    // Spoken as well as drawn: a caption a sighted reader gets is a caption everyone gets.
    val source = viewModel.sourceName(publication)
        ?.let { stringResource(R.string.library_cell_source, it) }

    Column(
        // One label for the whole cell. Read as three elements it would announce
        // the title, then the format, then an unlabelled image.
        modifier = modifier
            .fillMaxWidth()
            // A publication that cannot be read is not tappable. Opening it only
            // to show the same refusal twice wastes the user's tap.
            .then(
                when {
                    // While the reader is picking, a tap picks -- even a publication that
                    // cannot be opened, which can still be shelved and marked read. A cover
                    // that opened the reader mid-selection would throw away every pick.
                    isPicked != null -> Modifier.clickable { onToggle(publication) }

                    // `collections-and-reading-lists`: a publication "may belong to any
                    // number of collections", and a long press is where a reader says so.
                    publication.isOpenable -> Modifier.combinedClickable(
                        onClick = { onOpen(publication) },
                        onLongClick = { onAddToShelf?.invoke(publication) },
                    )

                    else -> Modifier
                },
            )
            .semantics {
                contentDescription = listOfNotNull(
                    publication.displayTitle,
                    subtitle,
                    publication.format.displayName,
                    source,
                ).joinToString(", ")
                // Spoken, because a tick in the corner of a cover is invisible to
                // TalkBack and "is this one picked" is the only question selection mode
                // asks.
                if (isPicked != null) selected = isPicked
            },
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Surface(
            // 2:3 is the comic and book proportion. Fixing it here means a cell
            // reserves its space before its cover arrives, so the grid does not
            // reflow as images land.
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
            color = palette.surfaceRaised,
            shape = RoundedCornerShape(StoryArcRadius.md),
            // A hairline rather than a shadow: a pale cover on a pale surface
            // needs an edge, and a shadow under every cell reads as noise at grid
            // density.
            border = androidx.compose.foundation.BorderStroke(1.dp, palette.borderSubtle),
        ) {
            val fraction = viewModel.readFraction(publication)
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(StoryArcRadius.md)),
                )
            } else {
                // A set title rather than an empty rectangle. A grid of publications
                // with no cover art -- and plenty of EPUBs carry none -- was a wall of
                // identical cards labelled with a format, which is the one thing every
                // card in that wall had in common. The title is what tells them apart.
                // The format stays, smaller, because it is still the answer to "why is
                // there no picture".
                Box(modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = publication.displayTitle,
                        style = MaterialTheme.typography.titleSmall,
                        color = palette.textSecondary,
                        textAlign = TextAlign.Center,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(horizontal = StoryArcSpace.sm),
                    )
                    Text(
                        text = publication.format.displayName,
                        style = MaterialTheme.typography.labelSmall,
                        color = palette.textTertiary,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = StoryArcSpace.xs),
                    )
                }
            }

            // `library-browsing`: "its cover carries an unobtrusive progress
            // indicator", and "a fully read publication is distinguishable at a
            // glance without a label covering the artwork". A bar along the foot
            // does both — it never crosses the artwork, and a full one reads as
            // finished without a word on top of the cover.
            if (fraction != null) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .wrapContentHeight(Alignment.Bottom),
                ) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(3.dp)
                            .background(Color.Black.copy(alpha = 0.35f)),
                    )
                    Box(
                        Modifier
                            .fillMaxWidth(fraction.coerceIn(0f, 1f))
                            .height(3.dp)
                            .background(
                                if (fraction >= 1f) palette.textSecondary else palette.accent,
                            ),
                    )
                }
            }

            if (isPicked != null) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.TopEnd) {
                    PickMark(isPicked)
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
            Text(
                text = publication.displayTitle,
                style = MaterialTheme.typography.bodySmall,
                color = palette.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (subtitle != null) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            // `library-browsing`: a publication "shows its source only when more than one
            // source is configured". A line only some readers ever see, which is the point —
            // with one source it would be the same word under every cover.
            viewModel.sourceName(publication)?.let { source ->
                Text(
                    text = stringResource(R.string.library_cell_source, source),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/**
 * Whether a cover is one of the ones the reader has picked.
 *
 * A mark in the corner rather than a tint over the artwork: the artwork is the interface, and
 * a wash of accent colour across a cover hides the one thing the reader is using to tell it
 * from its neighbour.
 *
 * iOS's `PickMark` sits in the same corner.
 */
@Composable
internal fun PickMark(isPicked: Boolean, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Icon(
        imageVector = if (isPicked) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
        // Announced by the cell, which already speaks the title this belongs to.
        contentDescription = null,
        tint = if (isPicked) palette.accent else palette.textTertiary,
        modifier = modifier.padding(StoryArcSpace.xs),
    )
}

/** The second line: what distinguishes this cell from its neighbours. */
@Composable
private fun cellSubtitle(publication: Publication): String? = when {
    // Said plainly rather than shown as a broken cover. `publication-formats`
    // requires a named refusal, and a grid cell is where a user meets one.
    !publication.isOpenable -> stringResource(R.string.library_cell_cannot_open)

    publication.series != null && publication.series != publication.displayTitle ->
        publication.number?.let { "${publication.series} #$it" } ?: publication.series

    else -> publication.authors.firstOrNull()
}
