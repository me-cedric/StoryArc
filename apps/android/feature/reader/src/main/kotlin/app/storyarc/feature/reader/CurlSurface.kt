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
    /**
     * The pages at a display position, in screen order: one, or two for a spread.
     *
     * A function rather than the layout itself, the way [modelIndex] already is. The curl
     * needs to know how many pages make up the sheet it is turning (task 8.13, D14); it does
     * not need to know what a slot is or which way the reading order runs.
     */
    slotPages: (Int) -> List<Int>,
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
     * The sheet at a display position: one page, or a spread composited into the one texture
     * a curl can turn (task 8.13, D14). The border trim [SinglePage] applies is baked in;
     * sharpness and colour are not, because [CurledPages] draws those live.
     */
    @Composable
    fun curlPage(display: Int?): Bitmap? = rememberSpreadTexture(
        pages = display?.let(slotPages).orEmpty(),
        raw = { viewModel.image(it) },
        trimsBorders = { adjustments.trimmingBorders(it !in uncropped).cropsBorders },
    )

    /** A neighbouring sheet, or a matte placeholder at its ratio -- twice as wide for a pair. */
    @Composable
    fun curlSheet(display: Int?): Bitmap? = CurlPlaceholder.sheet(display, { curlPage(it) }) {
        val slot = slotPages(it).size.coerceAtLeast(1)
        rememberCurlPlaceholder(PagePlaceholder.ratio(modelIndex(it), viewModel.decodedRatios()) * slot, matte)
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
