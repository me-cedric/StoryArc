package app.storyarc.feature.reader

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.navigation.HingeInsetPage
import app.storyarc.core.designsystem.navigation.HingeSpread
import app.storyarc.core.designsystem.navigation.rememberHingeSurface
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PageEntry
import app.storyarc.core.format.PdfTextPoint
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageReturn
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ScrollAxis
import app.storyarc.core.model.SpreadLayout
import kotlinx.coroutines.launch
import androidx.compose.runtime.MutableState
import app.storyarc.core.model.ShelfSettings
import app.storyarc.core.model.TransitionChoices
import kotlinx.coroutines.CoroutineScope

/**
 * The page itself, and whatever container the transition asks for, with the chrome over it.
 *
 * Moved out of [Pager] unchanged. The pager owns the state and the turns, and hands each to this
 * by name, so the code below reads the names it always read.
 */
@Composable
internal fun ReaderPageSurface(
    viewModel: ReaderViewModel,
    pages: List<PageEntry>,
    paging: Paging,
    layout: SpreadLayout,
    slotCount: Int,
    endSlot: Int,
    isRightToLeft: Boolean,
    matte: Color,
    adjustments: ImageAdjustments,
    uncropped: Set<Int>,
    fit: PageFit,
    /** D6: the pinch, as a multiple of the fit, to carry on while `fit` is fit-to-width. */
    carriedZoom: MutableState<Float?>,
    pdfText: PdfTextState?,
    choices: TransitionChoices,
    settings: ShelfSettings,
    resistance: RefusalResistance,
    keyboard: Modifier,
    isChromeVisible: Boolean,
    hasReachedEnd: Boolean,
    pageReturn: PageReturn,
    scope: CoroutineScope,
    slotIndex: (Int) -> Int,
    modelIndex: (Int) -> Int,
    handleTap: (Offset, IntSize) -> Unit,
    turn: (Int) -> Unit,
    reachEnd: () -> Unit,
    returnFromJump: () -> Unit,
    pdfDecoration: (Int) -> PdfPageDecoration,
    pdfSelectionHandler: (Int) -> ((PdfTextPoint, PdfTextPoint, Boolean) -> Unit)?,
    onClose: () -> Unit,
    onOpenMenu: () -> Unit,
    endScreen: @Composable () -> Unit,
) {
    var carriedZoomScale by carriedZoom
    /** One page, however it is being presented. */
    @Composable
    fun SinglePage(index: Int, stitch: ScrollAxis?, onTap: (Offset, IntSize) -> Unit) {
        // The zoom-resolution copy when one is held, the display one otherwise.
        val bitmap = viewModel.displayImage(index)
        ResolvePageMarks(pdfText, index)
        val trims = adjustments.trimmingBorders(index !in uncropped).cropsBorders
        when {
            bitmap != null -> ZoomablePage(
                // Cropped before it becomes an `ImageBitmap`, and sharpened there too on
                // the two versions with no shader for it (D9). See `pageDisplayBitmap`.
                bitmap = pageDisplayBitmap(bitmap, trims, adjustments.sharpness),
                pageId = pages.getOrNull(index)?.path ?: index.toString(),
                // The page number, not the archive entry's path. TalkBack read
                // "page10.png" aloud, which names a file inside a CBZ rather than a
                // page — and the reader never chose that name.
                contentDescription = stringResource(R.string.reader_page_label, index + 1, pages.size),
                fit = fit,
                // D6: only fit-to-width carries a pinch forward; every other mode
                // still resets on a turn, which `null` here leaves unchanged.
                carriedZoomScale = if (fit == PageFit.WIDTH) carriedZoomScale else null,
                isRightToLeft = isRightToLeft,
                adjustments = adjustments,
                onTap = onTap,
                // In a continuous scroll a page takes the height its own proportions
                // ask for. Fitting each one to the screen instead would put a band of
                // background between every pair, which is the opposite of the
                // "stitched with no gap" `comic-reader` asks for.
                stitch = stitch,
                onZoom = { scale, overFit ->
                    viewModel.holdZoom(scale, index)
                    if (fit == PageFit.WIDTH) carriedZoomScale = overFit
                },
                decoration = pdfDecoration(index),
                onSelect = pdfSelectionHandler(index),
            )
            // A page that is not drawn still has to accept a tap: a reader who lands
            // on a skipped page must be able to turn away from it.
            // `page-transitions`: a turn runs "against a placeholder holding the
            // correct aspect ratio, so the turn does not jump when the content
            // arrives". In a paged mode the page is screen-sized either way; in a
            // stitched scroll a screen-sized placeholder becomes a page-sized item
            // the moment it decodes, and every page below it lurches.
            else -> Box(
                modifier = Modifier
                    .then(
                        // The nearest decoded page's own ratio, not a flat comic-page
                        // guess — a webtoon strip is many times taller than wide. See
                        // `PagePlaceholder`.
                        when (stitch) {
                            ScrollAxis.VERTICAL -> Modifier
                                .fillMaxWidth()
                                .aspectRatio(PagePlaceholder.ratio(index, viewModel.decodedRatios()))
                            ScrollAxis.HORIZONTAL -> Modifier
                                .fillMaxHeight()
                                .aspectRatio(PagePlaceholder.ratio(index, viewModel.decodedRatios()))
                            null -> Modifier.fillMaxSize()
                        },
                    )
                    .tappable(onTap),
                contentAlignment = Alignment.Center,
            ) {
                if (viewModel.isUnavailable(index)) {
                    // Said, not blank, and named. `publication-formats` requires an
                    // undecodable page to show "a placeholder naming the codec": one
                    // page saying JPEG among ninety-nine that drew is a damaged entry in
                    // the file, and every page saying JPEG XL is a format this device
                    // has no decoder for. With no name the two look identical, and the
                    // only thing a reader could conclude was that the app was broken.
                    val codec = viewModel.codecName(index)
                    Message(
                        if (codec != null) {
                            stringResource(R.string.reader_page_unavailable_codec, codec)
                        } else {
                            stringResource(R.string.reader_page_unavailable)
                        },
                    )
                } else {
                    DelayedProgressIndicator()
                }
            }
        }
    }

    // `native-experience`: HingeSpread and HingeInsetPage keep a page off a folded window's hinge.
    val hingeSurface = rememberHingeSurface()

    /**
     * One slot: a page, or two facing pages.
     *
     * `comic-reader`: a pair is shown "side by side in the correct order for the reading
     * direction". Reading order is the publication's own either way — a manga spread
     * reads 4 then 5 exactly as a western one does — so only the screen order flips, and
     * it flips here rather than anywhere the pages are counted.
     */
    @Composable
    fun Page(display: Int, stitch: ScrollAxis? = null, insets: Boolean = true) {
        val spread = layout.slotAt(slotIndex(display))
        val trailing = spread?.trailing
        if (trailing == null || stitch != null) {
            // Curl insets its whole surface once, so the body it stands over is not inset twice.
            if (insets) HingeInsetPage(hingeSurface.hinge) { SinglePage(spread?.leading ?: 0, stitch, handleTap) }
            else SinglePage(spread?.leading ?: 0, stitch, handleTap)
            return
        }
        val onScreen =
            if (isRightToLeft) listOf(trailing, spread.leading) else listOf(spread.leading, trailing)
        HingeSpread(hingeSurface.hinge) { half ->
            SinglePage(onScreen[half], stitch = null) { point, size ->
                val (whole, area) = spreadTap(half, point, size)
                handleTap(whole, area)
            }
        }
    }

    /**
     * The page itself, and whatever container the transition asks for.
     *
     * A composable of its own so that it can be handed to a pane scaffold as a slot on a
     * wide window and drawn plainly on a narrow one, without either branch owning a second
     * copy of it.
     */
    @Composable
    fun PageSurface() {
        val surface = Modifier.fillMaxSize().then(hingeSurface.modifier).then(resistance.modifier)
        Box(surface, contentAlignment = Alignment.Center) {
            // One container per mode, over one page body. `page-transitions` treats the mode
            // as a property of the container, which is exactly what this is: the pager brings
            // its own gesture and edge resistance, the fade has no container at all, the scroll
            // is a lazy list, and the curl is a shader over two decoded pages.
            if (paging is Paging.Curled) HingeInsetPage(hingeSurface.hinge) {
                CurlSurface(
                    paging = paging,
                    slotCount = slotCount,
                    isRightToLeft = isRightToLeft,
                    matte = matte,
                    adjustments = adjustments,
                    uncropped = uncropped,
                    modelIndex = modelIndex,
                    slotPages = { layout.slotAt(slotIndex(it)).onScreen(isRightToLeft) },
                    viewModel = viewModel,
                    fit = fit,
                    carriedZoomScale = carriedZoomScale,
                    onTurn = { step -> scope.launch { paging.goTo(paging.current + step, animate = false) } },
                    onReachEnd = reachEnd,
                    modifier = keyboard,
                    endScreen = endScreen,
                    body = { Page(paging.current, insets = false) },
                )
            } else {
                // Slide and Fast fade animate a turn and report no end, so the position
                // bounds the count. Scroll opens no run: it has no discrete turn to bound
                // one, and `turnWindowMillis` is where that decision is stated and tested.
                ProbeTurns(choices.effective) { paging.current }
                when (paging) {
                    is Paging.Paged -> Ltr { HorizontalPager(state = paging.state, modifier = keyboard) { page ->
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            // `endSlot`: the extra slot past the last page (`Paging.kt`'s
                            // `count + 1`). Nothing to draw — reaching it opens
                            // `hasReachedEnd`, which covers this the same frame.
                            if (page - paging.lead != endSlot) Page(page - paging.lead)
                        }
                    } }

                    is Paging.Indexed -> AnimatedContent(
                    targetState = paging.index.intValue,
                    modifier = keyboard.fadeSwipe { turn(paging.current + it) },
                    // Short enough not to read as an animation, which is the whole point of
                    // the name. `page-transitions` uses this as the Reduce Motion substitute,
                    // so it must not become the thing it replaces.
                    transitionSpec = {
                        fadeIn(tween(FADE_MILLIS)) togetherWith fadeOut(tween(FADE_MILLIS))
                    },
                    label = "page",
                ) { page ->
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Page(page)
                    }
                }

                    is Paging.Scrolled -> if (choices.effective == PageTransition.VERTICAL_SCROLL) {
                        LazyColumn(state = paging.state, modifier = keyboard) {
                            // `slotCount + 1`: one slot past the last page, sized to the
                            // viewport (`fillParentMaxSize`) so scrolling into it reads as
                            // "one more screen" rather than a sliver. `comic-reader`: "a
                            // scroll past the last page reaches the end screen".
                            items(slotCount + 1) { item ->
                                val index = item - paging.lead
                                if (index == endSlot) {
                                    Box(Modifier.fillParentMaxSize())
                                    return@items
                                }
                                // `comic-reader` asks for the separator *between* pages, so the
                                // first page does not get one — a band above page one is a
                                // margin, not a separator.
                                if (settings.showsSeparator(aboveIndex = index)) {
                                    PageSeparator(ScrollAxis.VERTICAL, matte)
                                }
                                Page(index, stitch = ScrollAxis.VERTICAL)
                            }
                        }
                    } else Ltr {
                        LazyRow(state = paging.state, modifier = keyboard) {
                            items(slotCount + 1) { item ->
                                val index = item - paging.lead
                                if (index == endSlot) {
                                    Box(Modifier.fillParentMaxSize())
                                    return@items
                                }
                                if (settings.showsSeparator(aboveIndex = index)) {
                                    PageSeparator(ScrollAxis.HORIZONTAL, matte)
                                }
                                Page(index, stitch = ScrollAxis.HORIZONTAL)
                            }
                        }
                    }
                }
            }

            // Inside the pane, not over the window. On a wide window the browser of
            // every page sits beside this, and chrome spanning the whole window would
            // lay the reading controls across the thumbnails.
            // Never over the end screen, which is a screen of its own and answers for itself.
            AnimatedVisibility(
                visible = isChromeVisible && !hasReachedEnd,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                // Two controls, and everything the other nine used to do is one tap behind
                // the second of them. See `ReaderChrome.kt` and `ReaderMenuSheet.kt`.
                ReaderChrome(onClose = onClose, onOpenMenu = onOpenMenu)
            }

            // The way back from a jump, over the page.
            //
            // **Why this one control is over the page and the count is still two.** The
            // two-control count in `comic-reader` is about what a *centre tap reveals*; this
            // is armed by a jump the reader just made and disarmed by taking it. The scenario
            // that asks for it puts it after the menu has been dismissed by the same gesture
            // — "releasing jumps there and dismisses the menu, with a control to return to
            // the previous position" — so there is nowhere else it can be.
            //
            // It names the page rather than saying "Back", because by the time a reader
            // notices they have lost their place they no longer remember what it was.
            pageReturn.mark?.let { mark ->
                TextButton(
                    onClick = returnFromJump,
                    colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .safeDrawingPadding()
                        .padding(bottom = StoryArcSpace.xxl),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.Undo,
                        contentDescription = null,
                        modifier = Modifier.padding(end = StoryArcSpace.xs),
                    )
                    Text(stringResource(R.string.reader_return, mark + 1))
                }
            }
        }
    }

    PageSurface()
}

/**
 * The break between two pages in a continuous scroll.
 *
 * `comic-reader`: pages are "stitched with no gap by default, with an option to show a
 * separator". A band of the matte with a hairline through it, rather than a hairline on
 * its own: a black line between two black-bordered pages is invisible and so is a white
 * one between two white ones, and the matte is the colour the reader has already said
 * belongs between the artwork and the screen.
 *
 * iOS's `PageSeparator` is the same band.
 */
@Composable
private fun PageSeparator(
    axis: ScrollAxis,
    /** What shows around the page, which is what shows between two of them. */
    matte: Color,
    modifier: Modifier = Modifier,
) {
    // Enough to read as a deliberate break at arm's length, and not so much that a
    // webtoon stops reading as one strip.
    val band = 10.dp
    Box(
        modifier = modifier
            .then(
                if (axis == ScrollAxis.VERTICAL) {
                    Modifier.fillMaxWidth().height(band)
                } else {
                    Modifier.fillMaxHeight().width(band)
                },
            )
            .background(matte),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .then(
                    if (axis == ScrollAxis.VERTICAL) {
                        Modifier.fillMaxWidth().height(1.dp)
                    } else {
                        Modifier.fillMaxHeight().width(1.dp)
                    },
                )
                .background(LocalStoryArcPalette.current.borderSubtle),
        )
    }
}
