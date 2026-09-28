package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize
import app.storyarc.core.model.PageFit

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

    /** A double tap: in to [DOUBLE_TAP] centred on the point, or back out to fit. */
    /**
     * Toggles between the chosen fit and a zoom about the tapped point.
     *
     * Decision D5: "fit" is the chosen mode's own scale, not a fixed 1 — fit-to-width
     * and fit-to-height are each greater than 1, and comparing against a fixed [FIT]
     * zoomed a page that was already at its chosen fit further in on the first
     * double-tap instead of the second. [fitting] is what both the comparison and the
     * reset target need: the mode's own scale, and the offset that opens it correctly.
     */
    fun doubleTapped(at: Offset, page: PageBounds, fit: PageFit): PageZoom {
        val fitted = fitting(fit, page)
        if (isZoomedPastFit(scale, fitted.scale)) return fitted
        return PageZoom(DOUBLE_TAP, (page.centre - at) * DOUBLE_TAP).bounded(page)
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
    }
}
