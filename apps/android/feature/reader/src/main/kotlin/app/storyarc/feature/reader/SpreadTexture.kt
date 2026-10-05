package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.RectF
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import app.storyarc.core.model.Spread
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * A spread's two pages, composited into the one texture a curl can turn.
 *
 * D14. The curl deforms a *surface*, and a surface is one texture, so a slot holding two
 * facing pages had to become one picture before `isPairing` could include Curl. Until then
 * Curl was excluded from the pairing and a reader in landscape lost the spread the moment they
 * chose it -- which is the other half of `comic-reader`'s rule that a pair is "never split
 * across two turns".
 *
 * **Equal halves, because every other container draws equal halves.** `HingeSpread` gives each
 * page an equal share of the width, and `spreadTap` says so in as many words: a tap in one
 * half is a tap in the same place on a screen twice as wide. A composite that sized each half
 * to its own page would draw a spread the reader has seen in no other mode, and would move the
 * tap zones with it.
 *
 * The arithmetic is separated from the drawing so it can be asserted without a bitmap, the way
 * `SpreadLayout` and `CurlTurn` are. iOS's `SpreadTexture` is the twin.
 */
internal object SpreadTexture {

    /** The composite's pixel size, and the width one half gets. */
    data class Area(val width: Int, val height: Int, val half: Int)

    /**
     * The tallest page sets the height, and the widest page at that height sets the half, so
     * neither page is enlarged past its own resolution by more than the other demands.
     */
    fun area(pages: List<Pair<Int, Int>>): Area {
        val height = pages.maxOfOrNull { it.second } ?: 0
        val half = pages.maxOfOrNull { (width, pageHeight) ->
            if (pageHeight > 0) (width.toFloat() * height / pageHeight).roundToInt() else 0
        } ?: 0
        return Area(width = half * pages.size, height = height, half = half)
    }

    /**
     * Where one page lands inside the half that starts at [x]: fitted, and centred in both
     * directions, which is what a page does inside its own half of a spread.
     */
    fun placed(page: Pair<Int, Int>, x: Int, half: Int, height: Int): RectF {
        val (pageWidth, pageHeight) = page
        if (pageWidth <= 0 || pageHeight <= 0 || half <= 0 || height <= 0) return RectF()
        val scale = min(half.toFloat() / pageWidth, height.toFloat() / pageHeight)
        val width = pageWidth * scale
        val fitted = pageHeight * scale
        val left = x + (half - width) / 2f
        val top = (height - fitted) / 2f
        return RectF(left, top, left + width, top + fitted)
    }

    /**
     * The pages of one slot, in screen order, as a single texture.
     *
     * One page is handed back untouched: a slot that is not a pair pays nothing for this, and
     * `page-transitions`' *Memory during a curl* holds a composite only where a spread is
     * actually on screen.
     */
    fun composite(onScreen: List<Bitmap>): Bitmap? {
        if (onScreen.size < 2) return onScreen.firstOrNull()
        val pages = onScreen.map { it.width to it.height }
        val area = area(pages)
        if (area.width <= 0 || area.height <= 0) return null
        val texture = Bitmap.createBitmap(area.width, area.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(texture)
        onScreen.forEachIndexed { position, page ->
            canvas.drawBitmap(
                page,
                Rect(0, 0, page.width, page.height),
                placed(pages[position], x = position * area.half, half = area.half, height = area.height),
                null,
            )
        }
        return texture
    }
}

/**
 * The pages of a slot in *screen* order.
 *
 * Reading order is the publication's own either way -- a manga spread reads 4 then 5 exactly
 * as a western one does -- so only the screen order flips, and it flips here, where the
 * composite is built, rather than anywhere the pages are counted.
 */
internal fun Spread?.onScreen(isRightToLeft: Boolean): List<Int> {
    val pages = this?.pages.orEmpty()
    return if (isRightToLeft) pages.reversed() else pages
}

/**
 * The sheet for one slot, composited once per set of pages rather than once per frame.
 *
 * [pages] is already in screen order. Null until *every* page in the slot has decoded: half a
 * spread is not a sheet, and drawing one while the other half arrives would turn a page the
 * reader has not seen -- the caller answers that with the placeholder `page-transitions` asks
 * for.
 *
 * The remember is keyed on the *undecorated* bitmaps and the trim flags, both of which the
 * view model holds stable across a recomposition. Keying it on the cropped copies instead
 * would rebuild the composite on every frame of every turn, because a crop is a fresh bitmap.
 */
@Composable
internal fun rememberSpreadTexture(
    pages: List<Int>,
    raw: (Int) -> Bitmap?,
    trimsBorders: (Int) -> Boolean,
): Bitmap? {
    val decoded = pages.mapNotNull(raw)
    if (pages.isEmpty() || decoded.size != pages.size) return null
    val trims = pages.map(trimsBorders)
    return remember(decoded, trims) {
        SpreadTexture.composite(decoded.mapIndexed { at, page -> page.cropped(trims[at]) })
    }
}
