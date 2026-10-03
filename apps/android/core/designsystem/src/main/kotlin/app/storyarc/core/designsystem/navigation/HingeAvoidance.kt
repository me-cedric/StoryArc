package app.storyarc.core.designsystem.navigation

/**
 * Keeping a reader's page off a vertical, separating hinge.
 *
 * `native-experience` 19.5: a window folded open across a vertical hinge gives
 * `Posture.separatingVerticalHingeBounds` a rectangle, in the window's own coordinates --
 * and until this file, nothing in `feature/reader` or `feature/epubreader` ever read it. A
 * folded device paired two portrait pages beside each other with the crease running
 * straight through whichever one of them landed on it, and a single page centred on the
 * whole window the same way, hinge included.
 *
 * The arithmetic below is local to whatever container is asking -- a hinge in window
 * coordinates minus that container's own position -- and takes plain numbers rather than
 * `androidx.compose.ui.geometry.Rect`, so it runs as a fast JVM unit test and so a caller
 * that already measured its hinge in pixels, like `feature/epubreader`'s `View`, never
 * converts to `Dp` and back for arithmetic that does not care about the unit.
 *
 * Both readers call the same two functions: [hingeSpreadSplit] for two pages shown side by
 * side, [hingeInset] for one page on its own. Neither reads a window or composes anything,
 * which is what lets `HingeAvoidanceTest` assert the rule without a device.
 */

/** A two-up spread's width split across a hinge: the two halves, and the gap between them. */
data class HingeSpreadSplit(val leadingWidth: Float, val gap: Float, val trailingWidth: Float) {
    init {
        require(leadingWidth >= 0f && gap >= 0f && trailingWidth >= 0f) {
            "a width or the gap went negative: $this"
        }
    }
}

/**
 * How a two-up spread splits across a hinge that falls inside its own container.
 *
 * Equal halves and no gap -- this function's whole answer before 19.5 -- whenever there is
 * nothing to split on: no hinge at all, or a hinge that misses this particular container,
 * which is the ordinary case on a window that has not folded open.
 *
 * @param containerWidth the full width the spread draws across.
 * @param hingeStart the hinge's near edge, in the same unit and the same origin as
 *   [containerWidth] (0 is this container's own leading edge) -- or `null` where there is no
 *   separating vertical hinge to avoid.
 * @param hingeEnd the hinge's far edge. Ignored when [hingeStart] is `null`.
 */
fun hingeSpreadSplit(containerWidth: Float, hingeStart: Float?, hingeEnd: Float?): HingeSpreadSplit {
    val half = (containerWidth / 2f).coerceAtLeast(0f)
    val noHinge = HingeSpreadSplit(half, 0f, half)
    if (hingeStart == null || hingeEnd == null) return noHinge
    val start = hingeStart.coerceIn(0f, containerWidth)
    val end = hingeEnd.coerceIn(0f, containerWidth)
    if (end <= start) return noHinge
    return HingeSpreadSplit(leadingWidth = start, gap = end - start, trailingWidth = containerWidth - end)
}

/** Where a single page sits so its own focal area never straddles a hinge: a width, and which edge it is pinned to. */
data class HingeInset(val width: Float, val atStart: Boolean)

/**
 * The inset for a single page, derived from an already-computed [split].
 *
 * `null` means draw the page exactly as before 19.5 -- full width, centred -- because
 * [split] found nothing to avoid. Otherwise the page is pinned to whichever side of the
 * hinge has more room, at that side's own width, which is what keeps a roughly-centred
 * hinge from squeezing the page into the smaller half rather than simply moving it clear.
 */
fun hingeInset(split: HingeSpreadSplit): HingeInset? {
    if (split.gap <= 0f) return null
    return if (split.leadingWidth >= split.trailingWidth) {
        HingeInset(split.leadingWidth, atStart = true)
    } else {
        HingeInset(split.trailingWidth, atStart = false)
    }
}
