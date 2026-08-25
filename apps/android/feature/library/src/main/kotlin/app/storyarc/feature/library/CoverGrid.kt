package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * The cover grid.
 *
 * `library-browsing`: "the number of grid columns follows the available width, and
 * cover size stays within the readable range defined in the design tokens".
 * `GridCells.Adaptive` is what does that — a fixed column count would give a phone
 * postage stamps and a tablet a wall of enormous covers.
 *
 * iOS's `CoverGrid` uses the same bounds for the same reason.
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
     * What to do when a cover is tapped. The library does not open the reader
     * itself — a feature module never depends on another feature module, so the
     * app layer wires the two together.
     */
    onOpen: (Publication) -> Unit,
    modifier: Modifier = Modifier,
) {
    // The readable range. Below the minimum a cover stops being recognisable;
    // above the maximum a phone shows one and a half of them.
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
        columns = GridCells.Adaptive(minSize = 108.dp),
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
                ContinueReadingRow(continueReading, viewModel, onOpen, maxPixelSize)
            }
        }
        items(publications, key = { it.id }) { publication ->
            CoverCell(publication, viewModel, onOpen, maxPixelSize)
        }
    }
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
                    modifier = Modifier.width(128.dp),
                )
            }
        }
    }
}

/** One publication in the grid. */
@Composable
private fun CoverCell(
    publication: Publication,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    maxPixelSize: Int,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, maxPixelSize)
    }

    val subtitle = cellSubtitle(publication)

    Column(
        // One label for the whole cell. Read as three elements it would announce
        // the title, then the format, then an unlabelled image.
        modifier = modifier
            .fillMaxWidth()
            // A publication that cannot be read is not tappable. Opening it only
            // to show the same refusal twice wastes the user's tap.
            .then(
                if (publication.isOpenable) {
                    Modifier.clickable { onOpen(publication) }
                } else {
                    Modifier
                },
            )
            .semantics {
                contentDescription = listOfNotNull(
                    publication.displayTitle,
                    subtitle,
                    publication.format.displayName,
                ).joinToString(", ")
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
                // A placeholder that names the format rather than an empty
                // rectangle: while a cover loads, the format is the most useful
                // thing the cell knows, and it is the honest answer for a
                // publication that has none.
                Box(contentAlignment = Alignment.Center) {
                    Text(
                        text = publication.format.displayName,
                        style = MaterialTheme.typography.labelLarge,
                        color = palette.textTertiary,
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
        }
    }
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
