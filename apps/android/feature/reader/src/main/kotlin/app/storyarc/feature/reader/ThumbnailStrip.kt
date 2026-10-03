package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Badge
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
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlin.math.absoluteValue

/**
 * Every page, as a carousel that centres one.
 *
 * `page-browser-carousel`: "the thumbnail browser of a publication … SHALL [be] a
 * carousel that centres one page … drawn larger than the pages beside it … and marked
 * as current" and, with chapter markers, names the centred page's chapter above itself
 * and badges each chapter's first page.
 *
 * `HorizontalPager` rather than `HorizontalCenteredHeroCarousel`: the hero carousel
 * masks each item to its own clip shape, which would mask away the page number drawn
 * below it — design.md §1 names this as the carousel's own fallback. Every slot stays
 * the same width; the centred one only *looks* larger, scaled with `graphicsLayer` from
 * [androidx.compose.foundation.pager.PagerState.currentPageOffsetFraction].
 *
 * Lazy, and it has to be: a 300-page comic's strip would otherwise read 300 archive
 * entries to open. The cells ask the model for a thumbnail as they scroll into view,
 * and the model keeps a bounded number of them. iOS's `ThumbnailStrip` is the same
 * carousel with a `ScrollView` and `.scrollTargetBehavior(.viewAligned)`.
 */
@Composable
internal fun ThumbnailStrip(
    viewModel: ReaderViewModel,
    pageCount: Int,
    /** The page the reader is on, in the publication's own numbering. Marked as
     * current; the centred page is a separate, swipeable preview. */
    currentIndex: Int,
    /** Where a page-slider drag is heading, so the carousel can follow it. `null`
     * outside a drag, when the carousel is free to scroll on its own. */
    scrubbing: Int?,
    isRightToLeft: Boolean,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val cellWidth = 64.dp
    val palette = LocalStoryArcPalette.current
    var markers by remember { mutableStateOf<List<ChapterMarker>>(emptyList()) }
    LaunchedEffect(viewModel) { markers = viewModel.chapterMarkers() }
    val reduceMotion by viewModel.reduceMotionFlow.collectAsStateWithLifecycle()

    val initialSlot = remember {
        ChapterBrowser.displayIndex(currentIndex, pageCount, isRightToLeft)
    }
    val pagerState = rememberPagerState(initialPage = initialSlot) { pageCount }

    // `page-browser-carousel` §3: "the slider's value sets the carousel's centred page
    // with no animation" — `scrollToPage` jumps rather than animating.
    LaunchedEffect(scrubbing, pageCount, isRightToLeft) {
        val target = scrubbing ?: return@LaunchedEffect
        val slot = ChapterBrowser.displayIndex(target, pageCount, isRightToLeft)
        if (pagerState.currentPage != slot) pagerState.scrollToPage(slot)
    }

    val centredIndex = ChapterBrowser.displayIndex(pagerState.currentPage, pageCount, isRightToLeft)
    val chapterLabel = ChapterBrowser.chapterLabel(centredIndex, markers)

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
        ChapterNameHeader(chapterLabel)

        BoxWithConstraints(Modifier.fillMaxWidth()) {
            // Centres the first and last pages, the same way iOS's content margins do:
            // half the spare width on each side of one base-width cell.
            val density = LocalDensity.current
            val sideMargin = with(density) {
                val cellPx = cellWidth.toPx()
                val availablePx = maxWidth.toPx()
                ((availablePx - cellPx) / 2).coerceAtLeast(0f).toDp()
            }

            Ltr {
                HorizontalPager(
                    state = pagerState,
                    pageSize = PageSize.Fixed(cellWidth),
                    pageSpacing = StoryArcSpace.sm,
                    contentPadding = PaddingValues(horizontal = sideMargin),
                ) { page ->
                    val index = ChapterBrowser.displayIndex(page, pageCount, isRightToLeft)
                    ThumbnailCell(
                        viewModel = viewModel,
                        index = index,
                        isCurrent = index == currentIndex,
                        width = cellWidth,
                        badgeText = ChapterBrowser.badgeText(index, markers),
                        chapterName = chapterCellLabel(index, markers),
                        onSelect = onSelect,
                        // The page shrinks onto its number, and the number keeps its size:
                        // scaled with the page, a neighbour's number fell to 62.5%.
                        imageModifier = Modifier.graphicsLayer {
                            val scale = pageScale(pagerState.currentPage, page, pagerState.currentPageOffsetFraction)
                            scaleX = if (reduceMotion) 1f else scale
                            scaleY = if (reduceMotion) 1f else scale
                            transformOrigin = TransformOrigin(0.5f, 1f)
                        },
                        isCentredOutline = reduceMotion && page == pagerState.currentPage,
                        // The sheet's own ground, not the dark one `ThumbnailColumn` draws.
                        numberColor = palette.textTertiary,
                    )
                }
            }
        }
    }
}

/**
 * The scale a cell draws at: 1 at the centre, smaller the further `page` is from it.
 *
 * The same formula Compose's own pager samples use for this effect: 1 for the centred
 * page and 0.625 one page away, so the centred page is 1.6 times as wide as its
 * neighbours. Held outside the composable so `ThumbnailScaleTest` can reach it without
 * composing a pager.
 */
internal fun pageScale(currentPage: Int, page: Int, currentPageOffsetFraction: Float): Float {
    val distance = ((currentPage - page) + currentPageOffsetFraction).absoluteValue
    return 1f - (distance.coerceIn(0f, 1f) * 0.375f)
}

/**
 * The name above the carousel, for the chapter the centred page is in.
 *
 * Hidden from the accessibility tree rather than merely unfocusable — because each
 * cell's own content description already names its chapter. `page-browser-carousel`
 * §6: "a live label that is not focusable, so a moving carousel is not read twice".
 */
@Composable
private fun ChapterNameHeader(label: ChapterLabel?) {
    if (label == null) return
    val palette = LocalStoryArcPalette.current
    val text = when (label) {
        is ChapterLabel.Named -> label.title
        is ChapterLabel.Position -> stringResource(R.string.reader_chapter_number, label.position)
    }
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = palette.textSecondary,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter)
            .clearAndSetSemantics {},
    )
}

/** What a cell's content description adds to "Page %d" — the chapter the page at
 * `index` is in, read the same way the header above names it. */
@Composable
private fun chapterCellLabel(index: Int, markers: List<ChapterMarker>): String? =
    when (val label = ChapterBrowser.chapterLabel(index, markers)) {
        is ChapterLabel.Named -> label.title
        is ChapterLabel.Position -> stringResource(R.string.reader_chapter_number, label.position)
        null -> null
    }

/**
 * Every page, small, in a column beside the one being read.
 *
 * The same requirement as [ThumbnailStrip] — `comic-reader`'s "every page ... in a
 * scrollable strip with the current page marked" — answered for a window that has room
 * to show it *beside* the artwork rather than over it. A pane is tall and narrow, so a
 * grid is kept here rather than a carousel: `page-browser-carousel` names the centred
 * row's browser, and a supporting pane is the "beside the artwork" case design.md
 * leaves to this grid.
 *
 * Lazy for the same reason as the carousel: a three-hundred-page comic would otherwise
 * read three hundred archive entries to open, and the model keeps a bounded number of
 * the thumbnails the cells ask for.
 *
 * The same dark ground as the strip, for the same reason: the page numbers under the
 * cells are light, and the reader's own matte behind them may be any colour a reading
 * theme set.
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
    badgeText: String? = null,
    chapterName: String? = null,
    isCentredOutline: Boolean = false,
    imageModifier: Modifier = Modifier,
    numberColor: Color = Color.White.copy(alpha = 0.7f),
) {
    val palette = LocalStoryArcPalette.current
    var bitmap by remember(index) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(index) {
        if (bitmap == null) bitmap = viewModel.thumbnail(index)
    }

    val pageLabel = stringResource(R.string.reader_thumbnail_number, index + 1)
    val contentDescription = if (chapterName != null) "$pageLabel, $chapterName" else pageLabel

    Column(
        modifier = modifier
            .width(width)
            .selectable(selected = isCurrent, onClick = { onSelect(index) })
            .semantics {
                this.contentDescription = contentDescription
                this.selected = isCurrent
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        Box(
            modifier = imageModifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(StoryArcRadius.sm))
                .border(
                    width = when {
                        isCurrent -> 2.dp
                        isCentredOutline -> 2.dp
                        else -> 1.dp
                    },
                    color = when {
                        isCurrent -> palette.accent
                        isCentredOutline -> palette.accent.copy(alpha = 0.6f)
                        else -> palette.borderSubtle
                    },
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

            if (badgeText != null) {
                Badge(
                    containerColor = palette.surfaceRaised.copy(alpha = 0.85f),
                    contentColor = palette.accent,
                    modifier = Modifier.align(Alignment.TopStart).padding(StoryArcSpace.hair),
                ) { Text(badgeText) }
            }
        }

        Text(
            text = stringResource(R.string.reader_thumbnail_number, index + 1),
            style = MaterialTheme.typography.labelLarge,
            // The number's weight, not only the border: `native-experience` forbids
            // colour as the only signal, and a border is only colour.
            fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isCurrent) palette.accent else numberColor,
        )
    }
}
