package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.PageFit
import kotlin.math.abs

/**
 * A page as fit-to-screen sized it, inside the space available.
 *
 * Both numbers are needed. A tall scan on a wide screen is *letterboxed* — the
 * artwork is narrower than the viewport — and panning bounds computed from the
 * viewport instead of the artwork let the reader drag the page off the screen.
 */
internal data class PageBounds(
    val fittedWidth: Float,
    val fittedHeight: Float,
    val area: IntSize,
    /** The image's own width in pixels, for [PageFit.ORIGINAL]. */
    val pixelWidth: Float,
) {
    val centre: Offset get() = Offset(area.width / 2f, area.height / 2f)

    /** How far the page may be dragged, at a given scale, before artwork leaves. */
    fun slack(scale: Float): Offset = Offset(
        maxOf(0f, (fittedWidth * scale - area.width) / 2f),
        maxOf(0f, (fittedHeight * scale - area.height) / 2f),
    )

    companion object {
        /** The fit-to-screen size of an image, which is what a scale multiplies. */
        fun of(image: IntSize, area: IntSize): PageBounds {
            if (image.width <= 0 || image.height <= 0 || area.width <= 0 || area.height <= 0) {
                return PageBounds(0f, 0f, area, 0f)
            }
            val fit = minOf(
                area.width.toFloat() / image.width,
                area.height.toFloat() / image.height,
            )
            return PageBounds(
                fittedWidth = image.width * fit,
                fittedHeight = image.height * fit,
                area = area,
                pixelWidth = image.width.toFloat(),
            )
        }
    }
}

/**
 * How far a page is magnified, and where it has been dragged to.
 *
 * A value rather than two loose floats in a composable, because the arithmetic is
 * the part worth being sure about: zooming about a point that is not the centre
 * means moving the translation to compensate, and getting the sign wrong sends the
 * page off the screen. It is pure, so it is tested on the JVM.
 *
 * The page is drawn scaled about its own centre with [offset] applied afterwards,
 * so a content point `p` lands at `centre + (p - centre) * scale + offset`.
 */
internal data class PageZoom(
    val scale: Float = FIT,
    val offset: Offset = Offset.Zero,
) {
    val isMagnified: Boolean get() = scale > FIT

    /**
     * A pinch.
     *
     * `comic-reader`: "the page zooms about the pinch centre". Keeping the content
     * under the fingers still is what that means arithmetically.
     */
    fun pinched(centroid: Offset, zoomChange: Float, pan: Offset, page: PageBounds): PageZoom {
        val next = (scale * zoomChange).coerceIn(FIT, MAXIMUM)
        val fromCentre = centroid - page.centre
        val kept = fromCentre - (fromCentre - offset) * (next / scale)
        return PageZoom(next, kept + pan).bounded(page)
    }

    /**
     * A point on the screen, back in the page's own unscaled coordinates.
     *
     * The inverse of the transform in this type's own note: the page is drawn scaled about its
     * centre with [offset] applied afterwards, so undoing it is subtract, unscale, re-centre.
     *
     * What a selection needs. A finger reports where it is on the *screen*, and the words it is
     * over are at a fixed place on the *page* -- the two are only the same at fit scale with
     * nothing panned, which is the one state a reader who has zoomed in to read is not in.
     */
    fun unprojected(point: Offset, page: PageBounds): Offset =
        page.centre + (point - page.centre - offset) / scale

    /**
     * Toggles between the chosen fit and a zoom about the tapped point.
     *
     * Decision D5: "fit" is the chosen mode's own scale, not a fixed 1 — fit-to-width
     * and fit-to-height are each greater than 1, and comparing against a fixed [FIT]
     * zoomed a page that was already at its chosen fit further in on the first
     * double-tap instead of the second. [fitting] is what both the comparison and the
     * reset target need: the mode's own scale, and the offset that opens it correctly.
     *
     * The zoom in is [DOUBLE_TAP] times that fit, not a fixed scale: fit-to-width in
     * landscape can already sit above 2.5, and a fixed 2.5 zoomed out. It centres the
     * *content* under the finger, read back through the current zoom with [unprojected]:
     * at fit-to-width the screen point and the page point differ by the fit's own scale
     * and offset.
     */
    fun doubleTapped(at: Offset, page: PageBounds, fit: PageFit): PageZoom {
        val fitted = fitting(fit, page)
        if (isZoomedPastFit(scale, fitted.scale)) return fitted
        val target = (fitted.scale * DOUBLE_TAP).coerceAtMost(MAXIMUM)
        return PageZoom(target, (page.centre - unprojected(at, page)) * target).bounded(page)
    }

    /**
     * Whether the page takes a one-finger pan, rather than leaving it to a turn.
     *
     * D33 (task 8.16): in Curl the page body owns the finger first. A page wider than the
     * screen pans whichever way the finger goes, so a zoomed page pans and does not turn. A
     * page only taller than the screen, at fit-to-width, pans a finger that moves more down
     * than across, and leaves a sideways one to the curl or the pager. A page with no slack
     * at all takes nothing. iOS's `pagePanTurns` is the same rule from the other side.
     */
    fun claimsPan(pan: Offset, page: PageBounds): Boolean {
        // A pixel of rounding is not slack: fit-to-width multiplies back to the width
        // through a float, and a hair over it would claim every sideways finger.
        val slack = page.slack(scale)
        if (slack.x > SLACK_PIXELS) return true
        return slack.y > SLACK_PIXELS && abs(pan.y) >= abs(pan.x)
    }

    /**
     * The rectangle the page is fitted inside, on screen, at this zoom.
     *
     * The image fills the area and is fitted inside it, then scaled about its centre and
     * moved by [offset]. So the page lies fitted inside the area scaled the same way, which
     * is the rectangle the curl's shader has to fit the sheet into for a turn to start on the
     * page the reader was looking at.
     */
    fun frame(page: PageBounds): Rect {
        val width = page.area.width * scale
        val height = page.area.height * scale
        val left = page.centre.x - width / 2f + offset.x
        val top = page.centre.y - height / 2f + offset.y
        return Rect(left, top, left + width, top + height)
    }

    /**
     * Keeps the artwork over the screen.
     *
     * The bound is the *artwork's* overhang, not the viewport's: a letterboxed page
     * has less to give than the screen is wide.
     */
    fun bounded(page: PageBounds): PageZoom {
        val slack = page.slack(scale)
        return copy(
            offset = Offset(
                offset.x.coerceIn(-slack.x, slack.x),
                offset.y.coerceIn(-slack.y, slack.y),
            ),
        )
    }

    companion object {
        const val FIT = 1f

        /** Enough to read the lettering on a dense page, not so far the panel is lost. */
        const val DOUBLE_TAP = 2.5f

        const val MAXIMUM = 6f

        /** How much overhang, in pixels, counts as room to pan. See [claimsPan]. */
        const val SLACK_PIXELS = 1f

        /**
         * Whether a double-tap should zoom back to the fit scale, rather than in from it.
         *
         * The tolerance absorbs the rounding [fitting] carries, which an exact comparison
         * would read as "past fit" forever. iOS's `isZoomedPastFit` is the same rule.
         */
        fun isZoomedPastFit(currentScale: Float, fitScale: Float): Boolean =
            currentScale > fitScale * 1.01f

        /**
         * Where a fit mode starts.
         *
         * `comic-reader` lists four fit modes and, separately, free zoom. Expressing
         * a mode as a scale rather than as its own layout is what lets the two share
         * one number: pinching out of fit-to-width is just a larger scale, and
         * pinching back lands on the mode again.
         *
         * Fit-to-width opens at the *top* of the page rather than its middle, which
         * is where reading starts.
         */
        fun fitting(fit: PageFit, page: PageBounds): PageZoom {
            val scale = fit.scale(
                fittedWidth = page.fittedWidth,
                fittedHeight = page.fittedHeight,
                viewportWidth = page.area.width.toFloat(),
                viewportHeight = page.area.height.toFloat(),
                pixelWidth = page.pixelWidth,
            ).coerceIn(FIT, MAXIMUM)

            val slack = page.slack(scale)
            return PageZoom(scale, Offset(0f, slack.y))
        }

        /**
         * The scale a page opens at: the chosen fit's own scale, or a carried pinch.
         *
         * Decision D6: "zoom level" means the pinched scale, and in fit-to-width it
         * "carries to the next page" rather than resetting on every turn — every
         * other mode still resets, which is [fitting] alone.
         *
         * [carried] is the pinch as a multiple of the last page's own fit, not a raw
         * scale: a raw scale is relative to each page's fit-to-screen, which moves with
         * the page's shape, and every page reports the scale it opened at — so a page at
         * its plain fit carried that fit into a narrower page and opened it magnified. A
         * multiple at the fit, within [isZoomedPastFit]'s tolerance, carries nothing.
         */
        fun openingScale(fitScale: Float, carried: Float?, mode: PageFit): Float {
            if (mode != PageFit.WIDTH || carried == null || !isZoomedPastFit(carried, FIT)) {
                return fitScale
            }
            return (fitScale * carried).coerceAtMost(MAXIMUM)
        }

        /**
         * The zoom a page opens at, carrying a pinch forward where [openingScale] says to.
         *
         * A carried zoom opens against the side its reading order starts from — the
         * right, under right-to-left — rather than always the left, the way [fitting]
         * alone does.
         */
        fun carrying(fit: PageFit, page: PageBounds, carried: Float?, isRightToLeft: Boolean): PageZoom {
            val plain = fitting(fit, page)
            val scale = openingScale(plain.scale, carried, fit)
            if (scale == plain.scale) return plain
            val slack = page.slack(scale)
            return PageZoom(scale, Offset(if (isRightToLeft) -slack.x else 0f, slack.y))
        }
    }
}
