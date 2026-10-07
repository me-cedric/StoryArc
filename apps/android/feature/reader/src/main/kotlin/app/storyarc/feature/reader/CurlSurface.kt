package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageFit

@Composable
internal fun CurlSurface(
    paging: Paging.Curled,
    slotCount: Int,
    isRightToLeft: Boolean,
    matte: Color,
    adjustments: ImageAdjustments,
    uncropped: Set<Int>,
    modelIndex: (Int) -> Int,
    slotPages: (Int) -> List<Int>,
    viewModel: ReaderViewModel,
    /** The reader's fit, and the pinch fit-to-width carries, for where a sheet opens. */
    fit: PageFit,
    carriedZoomScale: Float?,
    onTurn: (Int) -> Unit,
    /** D10: the last page lifted off the end screen, which now opens. */
    onReachEnd: () -> Unit,
    modifier: Modifier = Modifier,
    /** The end-of-publication screen, under the last page while it lifts. */
    endScreen: @Composable () -> Unit = {},
    /** D33: the reader's normal page body, drawn at rest. */
    body: @Composable () -> Unit = {},
) {
    @Composable
    fun curlPage(display: Int?): Bitmap? = rememberSpreadTexture(
        pages = display?.let(slotPages).orEmpty(),
        raw = { viewModel.image(it) },
        trimsBorders = { adjustments.trimmingBorders(it !in uncropped).cropsBorders },
    )

    @Composable
    fun curlSheet(display: Int?): Bitmap? = CurlPlaceholder.sheet(display, { curlPage(it) }) {
        val slot = slotPages(it).size.coerceAtLeast(1)
        rememberCurlPlaceholder(PagePlaceholder.ratio(modelIndex(it), viewModel.decodedRatios()) * slot, matte)
    }

    /**
     * Where the sheet at [display] lies flat once it is the page on screen.
     *
     * A single page opens at the reader's fit, so the turn lands on exactly the rectangle
     * the page body then draws. A spread is two pages side by side, and its one composited
     * sheet is fitted to the whole area instead.
     */
    fun opens(display: Int?): (Bitmap, IntSize) -> Rect? = { sheet, area ->
        if (display == null || slotPages(display).size > 1) {
            null
        } else {
            val bounds = PageBounds.of(IntSize(sheet.width, sheet.height), area)
            val carried = if (fit == PageFit.WIDTH) carriedZoomScale else null
            PageZoom.carrying(fit, bounds, carried, isRightToLeft).frame(bounds)
        }
    }

    val next = adjacentDisplayIndex(paging.current, 1, slotCount, isRightToLeft)
    val behind = adjacentDisplayIndex(paging.current, -1, slotCount, isRightToLeft)
    // A spread is two pages, so neither one's frame is the sheet's: the sheet is fitted to
    // the whole area instead.
    val isSpread = slotPages(paging.current).size > 1
    val frame = remember { CurlFrame() }

    CurledPages(
        page = curlPage(paging.current),
        beneath = curlSheet(adjacentDisplayIndex(paging.current, 1, slotCount, isRightToLeft)),
        previous = curlSheet(adjacentDisplayIndex(paging.current, -1, slotCount, isRightToLeft)),
        isRightToLeft = isRightToLeft,
        matte = matte,
        adjustments = adjustments,
        isUnavailable = viewModel.isUnavailable(modelIndex(paging.current)),
        codecName = viewModel.codecName(modelIndex(paging.current)),
        // D10: past the last page the end screen is the next sheet, and lifting the page
        // off it opens it.
        onTurned = { if (next == null) onReachEnd() else onTurn(readingOrderStep(1, isRightToLeft)) },
        onTurnedBack = { onTurn(readingOrderStep(-1, isRightToLeft)) },
        progress = paging.progress,
        modifier = modifier,
        endsHere = next == null,
        pageFrame = { if (isSpread) null else frame.read() },
        beneathOpens = opens(next),
        previousOpens = opens(behind),
        endScreen = endScreen,
        body = { CompositionLocalProvider(LocalCurlFrame provides frame) { body() } },
    )
}
