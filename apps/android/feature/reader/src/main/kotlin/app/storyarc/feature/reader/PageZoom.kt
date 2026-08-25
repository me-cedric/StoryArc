package app.storyarc.feature.reader

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.IntSize

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
    fun pinched(centroid: Offset, zoomChange: Float, pan: Offset, area: IntSize): PageZoom {
        val next = (scale * zoomChange).coerceIn(FIT, MAXIMUM)
        val centre = centreOf(area)
        val fromCentre = centroid - centre
        val kept = fromCentre - (fromCentre - offset) * (next / scale)
        return PageZoom(next, kept + pan).bounded(area)
    }

    /**
     * A double tap: in to [DOUBLE_TAP] centred on the point, or back out to fit.
     */
    fun doubleTapped(at: Offset, area: IntSize): PageZoom {
        if (isMagnified) return PageZoom()
        val centre = centreOf(area)
        return PageZoom(DOUBLE_TAP, (centre - at) * DOUBLE_TAP).bounded(area)
    }

    /**
     * Keeps the page over the screen.
     *
     * At fit scale there is nowhere to pan to, so the offset is zero — otherwise a
     * drag that started while zoomed would leave the page off-centre after zooming
     * back out.
     */
    fun bounded(area: IntSize): PageZoom {
        if (!isMagnified) return PageZoom(scale, Offset.Zero)
        val maxX = area.width * (scale - FIT) / 2f
        val maxY = area.height * (scale - FIT) / 2f
        return copy(offset = Offset(offset.x.coerceIn(-maxX, maxX), offset.y.coerceIn(-maxY, maxY)))
    }

    private fun centreOf(area: IntSize) = Offset(area.width / 2f, area.height / 2f)

    companion object {
        const val FIT = 1f

        /** Enough to read the lettering on a dense page, not so far the panel is lost. */
        const val DOUBLE_TAP = 2.5f

        const val MAXIMUM = 6f
    }
}
