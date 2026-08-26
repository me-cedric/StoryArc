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
