package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * The compact list.
 *
 * `library-browsing` requires a list beside the grid: past a certain size a library
 * is scanned by title rather than recognised by artwork, and a screen of covers
 * holds nine rows where a list holds twenty.
 *
 * iOS's `CoverList` shows the same four things in the same order.
 */
@Composable
internal fun CoverList(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    modifier: Modifier = Modifier,
) {
    val thumbnailWidth = 44.dp
    val density = LocalDensity.current
    val maxPixelSize = remember(density) { with(density) { thumbnailWidth.roundToPx() } }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = StoryArcSpace.sm),
    ) {
        items(publications, key = { it.id }) { publication ->
            ListRow(publication, viewModel, onOpen, thumbnailWidth, maxPixelSize)
            HorizontalDivider()
        }
    }
}

@Composable
private fun ListRow(
    publication: Publication,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    thumbnailWidth: androidx.compose.ui.unit.Dp,
    maxPixelSize: Int,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, maxPixelSize)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            // A publication that cannot be read is not tappable. Opening it only
            // to show the same refusal a second time wastes the user's tap.
            .clickable(enabled = publication.isOpenable) { onOpen(publication) }
            // Material's 48 dp touch-target floor, per `native-experience`.
            .heightIn(min = StoryArcSpace.xxl + StoryArcSpace.lg)
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .width(thumbnailWidth)
                .aspectRatio(2f / 3f)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(StoryArcRadius.sm)),
            contentAlignment = Alignment.Center,
        ) {
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // A tinted rectangle rather than nothing: a row whose thumbnail is
                // absent should still look like a row with a thumbnail, or the
                // list gains a ragged left edge wherever a cover is missing.
                Box(modifier = Modifier.fillMaxSize().background(palette.surfaceRaised))
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
        ) {
            Text(
                text = publication.displayTitle,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = rowSubtitle(publication),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        viewModel.readFraction(publication)?.let { fraction ->
            // A number here rather than a bar: a list row is read, and "48%" is
            // quicker to read than a sliver of colour is to measure.
            Text(
                text = stringResource(R.string.library_cell_progress, (fraction * 100).toInt()),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textSecondary,
            )
        }
    }
}

/**
 * What distinguishes this row from its neighbours, format included: in a list the
 * artwork is too small to say what kind of publication this is.
 */
@Composable
private fun rowSubtitle(publication: Publication): String {
    val parts = buildList {
        if (!publication.isOpenable) add(stringResource(R.string.library_cell_cannot_open))
        val series = publication.series
        if (series != null && series != publication.displayTitle) {
            add(publication.number?.let { "$series #$it" } ?: series)
        } else {
            publication.authors.firstOrNull()?.let { add(it) }
        }
        add(publication.format.displayName)
    }
    return parts.joinToString(" · ")
}
