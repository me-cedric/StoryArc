package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.ImageAdjustments

/**
 * The curl container, and the three decoded sheets it is handed.
 *
 * Beside `ReaderScreen.kt` rather than inside it. That file is one of the three this
 * repository records as already past its line cap (`scripts/line-cap.mjs`): it may shrink
 * and it may not grow, so the curl's own growth had to land in a file of its own. iOS's
 * `ReaderContainers.curled` is the twin, and `CurlSheetWiringTest` reads this file for the
 * sheets the curl receives.
 */
@Composable
internal fun CurlSurface(
    paging: Paging.Curled,
    /** How many slots the publication lays out, which is what bounds a neighbouring sheet. */
    slotCount: Int,
    isRightToLeft: Boolean,
    /** What shows behind and beside the page. See [matteColour]. */
    matte: Color,
    /** The series' brightness, contrast, inversion, greyscale and sharpness. */
    adjustments: ImageAdjustments,
    /** The pages the reader asked to keep their borders. See `cropsThisPage`. */
    uncropped: Set<Int>,
    /** A display position turned back into the publication's own page number. */
    modelIndex: (Int) -> Int,
    viewModel: ReaderViewModel,
    /**
     * Commits a turn the curl has already rolled, by a reading-order step.
     *
     * Deliberately not `ReaderScreen`'s own `turn`: that route animates, and the fold it
     * would start is the fold that has just finished. See [Paging.Curled.goTo].
     */
    onTurn: (Int) -> Unit,
    /** A press that was not a drag: the caller decides what it means. */
    onTap: (Offset, IntSize) -> Unit,
    modifier: Modifier = Modifier,
) {
    /**
     * The decoded page at a display position, with the border trim [SinglePage] applies
     * baked in. Sharpness and colour are not baked: [CurledPages] draws them live.
     */
    @Composable
    fun curlPage(display: Int?): Bitmap? {
        val index = display?.let(modelIndex) ?: return null
        val raw = viewModel.image(index) ?: return null
        val trims = adjustments.trimmingBorders(index !in uncropped).cropsBorders
        return remember(raw, trims) { raw.cropped(trims) }
    }

    /** A neighbouring sheet, or a matte placeholder at its expected ratio while it decodes. */
    @Composable
    fun curlSheet(display: Int?): Bitmap? = CurlPlaceholder.sheet(display, { curlPage(it) }) {
        rememberCurlPlaceholder(PagePlaceholder.ratio(modelIndex(it), viewModel.decodedRatios()), matte)
    }

    CurledPages(
        page = curlPage(paging.current),
        // Reading-order steps: under right-to-left `paging.current + 1` is the previous page.
        beneath = curlSheet(adjacentDisplayIndex(paging.current, 1, slotCount, isRightToLeft)),
        previous = curlSheet(adjacentDisplayIndex(paging.current, -1, slotCount, isRightToLeft)),
        isRightToLeft = isRightToLeft,
        matte = matte,
        adjustments = adjustments,
        isUnavailable = viewModel.isUnavailable(modelIndex(paging.current)),
        codecName = viewModel.codecName(modelIndex(paging.current)),
        onTurned = { onTurn(readingOrderStep(1, isRightToLeft)) },
        onTurnedBack = { onTurn(readingOrderStep(-1, isRightToLeft)) },
        onTap = onTap,
        progress = paging.progress,
        modifier = modifier,
    )
}
