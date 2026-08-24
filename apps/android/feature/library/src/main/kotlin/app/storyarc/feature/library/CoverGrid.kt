package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.grid.GridCells
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

    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 108.dp),
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = StoryArcSpace.gutter,
            vertical = StoryArcSpace.md,
        ),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
    ) {
        items(publications, key = { it.id }) { publication ->
            CoverCell(publication, viewModel, onOpen, maxPixelSize)
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
