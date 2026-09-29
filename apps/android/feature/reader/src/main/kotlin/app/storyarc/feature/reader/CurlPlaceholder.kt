package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import kotlin.math.roundToInt

/**
 * The sheet a curl turns to while that page has not decoded.
 *
 * `page-transitions` "The next page is not ready": the turn "runs against a placeholder
 * holding the correct aspect ratio". Without one, the curl showed the outgoing page again
 * as the page beneath, and a backwards drag did nothing at all. iOS's `CurlPlaceholder`
 * is the same shape.
 */
internal object CurlPlaceholder {
    /**
     * The sheet at [display]: the decoded page, the placeholder while it decodes, or null
     * past either end of the publication. Null there is what stops the first page turning
     * back.
     */
    inline fun <T : Any> sheet(display: Int?, decoded: (Int) -> T?, placeholder: (Int) -> T): T? {
        val at = display ?: return null
        return decoded(at) ?: placeholder(at)
    }

    /** The short side, in pixels. The shader fits the sheet to the screen, so only the ratio counts. */
    const val SIDE = 64

    /** Width and height for a width-over-height [ratio], with [SIDE] as the short side. */
    fun size(ratio: Float): Pair<Int, Int> {
        val safe = if (ratio > 0f) ratio else PagePlaceholder.DEFAULT_RATIO
        return if (safe >= 1f) (SIDE * safe).roundToInt() to SIDE else SIDE to (SIDE / safe).roundToInt()
    }

    /** A sheet of [matte] at [ratio]. */
    fun bitmap(ratio: Float, matte: Color): Bitmap {
        val (width, height) = size(ratio)
        return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply { eraseColor(matte.toArgb()) }
    }
}

/** [CurlPlaceholder.bitmap], kept across frames for as long as the ratio and matte hold. */
@Composable
internal fun rememberCurlPlaceholder(ratio: Float, matte: Color): Bitmap =
    remember(ratio, matte) { CurlPlaceholder.bitmap(ratio, matte) }
