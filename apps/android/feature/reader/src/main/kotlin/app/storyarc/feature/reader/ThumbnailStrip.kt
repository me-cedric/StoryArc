package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * Every page, small, in a row.
 *
 * `comic-reader`: "every page is shown in a scrollable strip with the current page
 * marked, and tapping one jumps to it".
 *
 * Lazy, and it has to be: a 300-page comic's strip would otherwise read 300 archive
 * entries to open. The cells ask the model for a thumbnail as they scroll into view,
 * and the model keeps a bounded number of them.
 *
 * iOS's `ThumbnailStrip` is the same strip with a `LazyHStack`.
 */
@Composable
internal fun ThumbnailStrip(
    viewModel: ReaderViewModel,
    pageCount: Int,
    /** The page the reader is on, in the publication's own numbering. */
    currentIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val cellWidth = 64.dp
    val state = rememberLazyListState()

    // Opens on the page being read rather than at page one, which is the only
    // position a reader forty pages in would have to scroll away from.
    LaunchedEffect(currentIndex) { state.animateScrollToItem(currentIndex.coerceAtLeast(0)) }

    LazyRow(
        state = state,
        modifier = modifier
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.85f)),
        contentPadding = PaddingValues(StoryArcSpace.md),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(pageCount) { index ->
            ThumbnailCell(
                viewModel = viewModel,
                index = index,
                isCurrent = index == currentIndex,
                width = cellWidth,
                onSelect = onSelect,
            )
        }
    }
}

/**
 * Every page, small, in a column beside the one being read.
 *
 * The same requirement as [ThumbnailStrip] — `comic-reader`'s "every page ... in a
 * scrollable strip with the current page marked" — answered for a window that has room to
 * show it *beside* the artwork rather than over it. A row would be the wrong shape there: a
 * pane is tall and narrow, and a single line of thumbnails scrolling sideways inside it
 * would show four pages where a grid shows twenty.
 *
 * Lazy for the same reason as the strip: a three-hundred-page comic would otherwise read
 * three hundred archive entries to open, and the model keeps a bounded number of the
 * thumbnails the cells ask for.
 *
 * The same dark ground as the strip, for the same reason: the page numbers under the cells
 * are light, and the reader's own matte behind them may be any colour a reading theme set.
 */
@Composable
internal fun ThumbnailColumn(
    viewModel: ReaderViewModel,
    pageCount: Int,
    /** The page the reader is on, in the publication's own numbering. */
    currentIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state = rememberLazyGridState()

    // Opens on the page being read rather than at page one, which is the only position a
    // reader forty pages in would have to scroll away from.
    LaunchedEffect(currentIndex) { state.animateScrollToItem(currentIndex.coerceAtLeast(0)) }

    LazyVerticalGrid(
        // Adaptive rather than a fixed count: the pane is as wide as the window can spare,
        // and a fixed two columns would be cramped at 840 dp and wasteful at 1600.
        columns = GridCells.Adaptive(88.dp),
        state = state,
        modifier = modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.85f)),
        contentPadding = PaddingValues(StoryArcSpace.md),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        items(pageCount) { index ->
            ThumbnailCell(
                viewModel = viewModel,
                index = index,
                isCurrent = index == currentIndex,
                width = 88.dp,
                onSelect = onSelect,
            )
        }
    }
}

/**
 * The page the slider is heading for, while the finger is still down.
 *
 * `comic-reader`: "a thumbnail of the target page follows the drag". The thumbnail the
 * strip already has, at the size the strip already decodes: a scrub across a comic asks
 * for a page every few frames, and a full-size decode per frame is how a slider ends up
 * dropping them.
 *
 * iOS's `ScrubThumbnail` is the same preview.
 */
@Composable
internal fun ScrubThumbnail(
    viewModel: ReaderViewModel,
    index: Int,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var bitmap by remember(index) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(index) { bitmap = viewModel.thumbnail(index) }

    Box(
        modifier = modifier
            .width(72.dp)
            .aspectRatio(2f / 3f)
            .clip(RoundedCornerShape(StoryArcRadius.sm))
            .border(1.dp, palette.borderSubtle, RoundedCornerShape(StoryArcRadius.sm)),
    ) {
        val ready = bitmap
        if (ready != null) {
            Image(
                bitmap = ready.asImageBitmap(),
                // The page number beside it is this row's label, and a second
                // announcement of the same page would get in the way of the drag.
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // No spinner: the thumbnail arrives in a frame or two from the cache the
            // strip fills, and a spinner under a moving finger is a flicker.
            Box(Modifier.fillMaxSize().background(palette.surfaceRaised))
        }
    }
}

@Composable
private fun ThumbnailCell(
    viewModel: ReaderViewModel,
    index: Int,
    isCurrent: Boolean,
    width: androidx.compose.ui.unit.Dp,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var bitmap by remember(index) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(index) {
        if (bitmap == null) bitmap = viewModel.thumbnail(index)
    }

    Column(
        modifier = modifier
            .width(width)
            .selectable(selected = isCurrent, onClick = { onSelect(index) }),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(StoryArcRadius.sm))
                .border(
                    width = if (isCurrent) 2.dp else 1.dp,
                    color = if (isCurrent) palette.accent else palette.borderSubtle,
                    shape = RoundedCornerShape(StoryArcRadius.sm),
                ),
        ) {
            val ready = bitmap
            if (ready != null) {
                Image(
                    bitmap = ready.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // No spinner per cell: eight of them spinning while a strip scrolls
                // is worse than eight quiet rectangles.
                Box(Modifier.fillMaxSize().background(palette.surfaceRaised))
            }
        }

        Text(
            text = stringResource(R.string.reader_thumbnail_number, index + 1),
            style = MaterialTheme.typography.labelLarge,
            // The number's weight, not only the border: `native-experience` forbids
            // colour as the only signal, and a border is only colour.
            fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isCurrent) palette.accent else Color.White.copy(alpha = 0.7f),
        )
    }
}
