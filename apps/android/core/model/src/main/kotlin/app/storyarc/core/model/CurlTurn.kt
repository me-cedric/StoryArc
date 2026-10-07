package app.storyarc.core.model

import kotlin.math.abs

/**
 * How fast a finger has to be leaving the screen, forwards, for the turn to complete
 * anyway — in density-independent points per second, in turn-space.
 *
 * Not a raw pixel delta from the last event: that depends on both the display's refresh
 * rate and its density, so the same real flick was missed on a 120 Hz panel (half the
 * travel per event of a 60 Hz one) and read differently on every density. A judgement
 * call rather than a measured one — not measured on a device — but a velocity in
 * physical units is at least the same swipe wherever it runs, which a per-event pixel
 * count is not.
 */
internal const val FLICK_DP_PER_SECOND = 800f

/**
 * Where a page stands mid-turn, and what a finger does to it from there.
 *
 * Pulled out of the gesture so it can be tested without a touch screen, the way
 * `TurnDrag` is in the reflowable reader: this is the whole rule, and the rest of the comic
 * reader's `CurledPages` is Compose's pointer contract.
 *
 * In `:core:model` rather than `:feature:reader` because two readers turn a page with it: the
 * comic reader, and the EPUB reader's finger-driven curl over prose (task 8.12), which cannot
 * depend on another feature module. One rule for both is what makes a page of prose and a page
 * of a comic settle at the same point. The sheet's outline stays with the comic reader, which
 * is the one reader that draws it, as an extension there.
 */
object CurlTurn {

    /**
     * Travel in turn-space: positive is towards a completed turn.
     *
     * A right-to-left publication turns forward when the finger moves the other way, so
     * one sign carries the whole mirroring.
     */
    fun forward(travel: Float, isRightToLeft: Boolean): Float =
        if (isRightToLeft) travel else -travel

    /**
     * Where the page stands after [travel] pixels of drag from [base].
     *
     * The base is the whole point. `comic-reader` requires a drag begun during a settle
     * to take over "from the current position without the page snapping", so the drag is
     * an *offset* from where the page stands rather than an absolute reading of the
     * finger: a settle caught at 0.8 and nudged one pixel stays at 0.8, where reading the
     * finger alone would have put it at 0.001.
     *
     * It is also what lets a caught settle be pushed back. Clamping an absolute reading
     * at zero made every backwards move mean "no progress"; clamping base plus travel
     * makes it mean "less progress", which is the same gesture read correctly.
     *
     * @param base the page's progress when the finger took it over, 0 for a flat page.
     * @param travel raw horizontal pixels since the drag was recognised.
     * @param width what a whole turn is measured against. A width nothing has measured
     *   yet leaves the page where it stands rather than dividing by it.
     * @param canTurnBack false at the first page, where a backwards drag moves nothing.
     * @param canTurnForward false where [under] answers [Under.NOTHING]. D10: the last
     *   page of a publication lifts off its end screen, which is the next sheet, and
     *   nothing lifts where there is no sheet of any kind beneath.
     */
    fun progress(
        base: Float,
        travel: Float,
        width: Float,
        isRightToLeft: Boolean,
        canTurnBack: Boolean = true,
        canTurnForward: Boolean = true,
    ): Float {
        val floor = if (canTurnBack) -1f else 0f
        val ceiling = if (canTurnForward) 1f else 0f
        if (width <= 0f) return base.coerceIn(floor, ceiling)
        return (base + forward(travel, isRightToLeft) / width).coerceIn(floor, ceiling)
    }

    /**
     * Whether the finger left fast, in the direction the page is already going.
     *
     * Signed, and it has to be: a fast finger dragging a half-turned page *back* has said
     * it does not want the turn, and a fast finger dragging the page behind into view has
     * asked for that one. An unsigned flick answered both with "complete the forward turn".
     *
     * @param velocity dp/s in turn-space — already mirrored for right-to-left by the
     *   caller, through [forward], the same way [progress]'s `travel` is.
     */
    fun flicks(velocity: Float, progress: Float): Boolean =
        if (progress < 0f) velocity < -FLICK_DP_PER_SECOND else velocity > FLICK_DP_PER_SECOND

    /**
     * Which sheet the shader turns, which page lies under it, and at what forward progress.
     *
     * **A backwards turn is the forward projection, run on the page behind.** At a whole
     * turn back the previous page lies flat and fully in view, which is the forward
     * projection at rest; at nothing dragged it is folded entirely away and the current
     * page is what shows, which is the forward projection completed. So `1 + progress`
     * carries the whole of it, and the shader needs no second direction.
     *
     * Generic over the image type so the mapping can be asserted without a bitmap.
     */
    fun <T> sheets(progress: Float, page: T?, beneath: T?, previous: T?): Sheets<T> =
        if (progress < 0f) {
            Sheets(turning = previous, under = page, progress = 1f + progress)
        } else {
            Sheets(turning = page, under = beneath, progress = progress)
        }

    /** What [sheets] decided. */
    data class Sheets<T>(val turning: T?, val under: T?, val progress: Float)

    /**
     * Whether a released turn completes rather than springing back.
     *
     * Past halfway it completes; before it, it springs back. A flick completes whatever
     * the distance, because a fast finger has already said what it meant — and a page
     * that never left flat is not a turn at all, however fast the finger left it.
     */
    fun settles(progress: Float, isFlick: Boolean): Boolean =
        abs(progress) > 0.5f || (isFlick && abs(progress) > 0.05f)

    /** What a forward turn lifts the page off. iOS's `CurlTurn.Under` is the twin. */
    enum class Under {
        /** The next sheet of the publication, or its placeholder. */
        SHEET,

        /** The end-of-publication screen: D10 makes it the next sheet past the last page. */
        END_SCREEN,

        /** Nothing, so nothing lifts. */
        NOTHING,
    }

    /**
     * What lies under a forward turn of this page.
     *
     * @param endsHere true when no slot follows this one in reading order, so the
     *   publication's end screen comes next.
     */
    fun <T> under(beneath: T?, endsHere: Boolean): Under = when {
        beneath != null -> Under.SHEET
        endsHere -> Under.END_SCREEN
        else -> Under.NOTHING
    }
}
