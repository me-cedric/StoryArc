/*
 * How wide a cover is drawn, and therefore how many of them a window holds.
 *
 * This rule had three homes and now has one. `:feature:library` held it for the library
 * shelf, `:app` held a second copy for the Downloads shelf, and the second copy had already
 * drifted: it ignored the reader's font scale entirely, so at an accessibility text size the
 * Downloads shelf kept 104 dp columns while the library shelf widened to 146 — two shelves in
 * one app answering the same question differently, with captions wrapping hard inside the
 * narrow one. iOS had the identical divergence in `OnDeviceShelf`, where Apple's
 * accessibility audit reported it as five clipped labels.
 *
 * The copy existed because everything here was `internal` to `:feature:library`, so `:app`
 * could not call it however much it should. It lives in `:core:designsystem` now — the module
 * both of them already depend on, and where the rest of `design.md` already lives — as public
 * API. A shelf asks `rememberCoverColumns`; nobody restates the ladder.
 */
package app.storyarc.core.designsystem.grid

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/** The widest a cover is ever drawn at an ordinary font scale. See [coverMaximumWidth]. */
val COVER_MAXIMUM_WIDTH = 168.dp

/**
 * The font scale at which the reader has left the ordinary range.
 *
 * Android's own Font size slider stops at 1.3 outside accessibility settings, and the
 * larger steps (1.5, 1.8, 2.0) live behind them. iOS reads the same boundary as
 * `DynamicTypeSize.isAccessibilitySize`.
 */
private const val ACCESSIBILITY_FONT_SCALE = 1.3f

/**
 * How much wider a cover is drawn once the reader is at an accessibility font scale.
 *
 * A step, not a scale, and there are exactly two of them. Cover width and text size are not
 * the same quantity: multiplying the cell by the font would trade away the artwork — the
 * one thing this app says is the interface — to make room for words. What a cramped caption
 * actually needs is *one fewer column*, and a column is a step.
 *
 * 1.4 is chosen against the widths that bracket a phone. It takes a ~400 dp phone from
 * three columns to two — the caption goes from 112 dp, where `Harbour Lights #1` wraps and
 * its neighbours' series lines truncate, to 174 dp — and it leaves a 360 dp phone at the
 * two columns it already had rather than dropping it to one. `library-browsing` still wants
 * a grid at every text size; it is the truncation that has to go, not the shelf.
 *
 * iOS's `accessibilityCoverStep` is the same number for the same reason.
 */
private const val ACCESSIBILITY_COVER_STEP = 1.4f

/**
 * The narrowest a cover may be drawn, given the room the window has and how large the
 * reader has asked for text to be.
 *
 * `design.md` §4: "Minimum cover width scales by size class: 104 / 132 / 158 pt". One
 * number for every window is what left a 1400 dp tablet showing roughly eleven columns of
 * phone-sized covers — a shelf reads as a shelf at a size the room can afford, and a room
 * that got bigger should not simply hold more of the same postage stamps. Those three are
 * the answer at every ordinary font scale and are unchanged; [fontScale] only decides
 * whether the tier is taken as written or one step wider.
 *
 * The two width thresholds are Material's own medium (600 dp) and expanded (840 dp)
 * breakpoints, which is also where `StoryArcWindowClass` will grow its remaining cases.
 * Taken from the window's width rather than from a device check, for the reason
 * `WindowClass.kt` sets out at length: a multi-window slot, a rotation and a fold are all
 * the same event. The font scale is the second such event.
 */
fun coverMinimumWidth(windowWidthDp: Int, fontScale: Float = 1f): Dp {
    val tier = when {
        windowWidthDp >= 840 -> 158.dp
        windowWidthDp >= 600 -> 132.dp
        else -> 104.dp
    }
    return tier.steppedForFontScale(fontScale)
}

/**
 * The widest a cover is ever drawn. Above it a phone shows one and a half of them.
 *
 * The cap steps with the minimum, or it would become the thing that decides the layout: a
 * tablet at an accessibility font scale asks for 221 dp columns, and a cap still pinned at
 * 168 dp would grant the wider columns and then draw 168 dp covers inside them, leaving a
 * ragged strip of empty shelf down the trailing edge. iOS derives its maximum from its
 * minimum and gets this for nothing.
 */
fun coverMaximumWidth(fontScale: Float = 1f): Dp =
    COVER_MAXIMUM_WIDTH.steppedForFontScale(fontScale)

/**
 * This width, one accessibility step wider when the reader is past the ordinary range.
 *
 * Public because a shelf has more than covers on it: the continue-reading row is sized in
 * the same steps, and a row that kept its ordinary width while the grid beneath it widened
 * would be the one place on the screen still truncating its captions.
 *
 * Rounded to whole dp, so both platforms land on the same 146 / 185 / 221.
 */
fun Dp.steppedForFontScale(fontScale: Float): Dp =
    if (fontScale >= ACCESSIBILITY_FONT_SCALE) {
        (value * ACCESSIBILITY_COVER_STEP).roundToInt().dp
    } else {
        this
    }

/**
 * The columns a cover shelf lays out in this window, for this reader.
 *
 * Every shelf in the app asks this and no shelf answers it for itself — that is the whole
 * point of the function existing. The library shelf and the Downloads shelf are two views of
 * one library, and a reader who turns their text size up should not find that one of them
 * reflowed and the other did not.
 *
 * The *window's* width is what is measured, rather than the shelf's own: 600 and 840 are
 * Material's window size-class breakpoints, so measuring a content pane against them would
 * read a 900 dp window behind a navigation rail as a medium one.
 *
 * Both bounds, not just the minimum: [androidx.compose.foundation.lazy.grid.GridCells.Adaptive]
 * has no maximum, so a narrow window stretches its single column to the full width and one
 * cover fills the screen. [BoundedAdaptive] is the other half of the scenario.
 */
@Composable
fun rememberCoverColumns(): BoundedAdaptive {
    val density = LocalDensity.current
    val windowWidth = LocalWindowInfo.current.containerSize.width
    // The reader's text size is the second input to the cover size, not only the window's
    // width: three columns of caption on a phone at an accessibility font scale is a
    // recognisable cover under an unreadable label, which inverts what a caption is for.
    val fontScale = density.fontScale
    return remember(density, windowWidth, fontScale) {
        val widthDp = with(density) { windowWidth.toDp().value.toInt() }
        BoundedAdaptive(
            minSize = coverMinimumWidth(widthDp, fontScale),
            maxSize = coverMaximumWidth(fontScale),
        )
    }
}
