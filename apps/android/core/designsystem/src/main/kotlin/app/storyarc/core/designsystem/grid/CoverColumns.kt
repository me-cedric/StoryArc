/*
 * How wide a cover is drawn, and therefore how many of them a window holds.
 *
 * This rule had two homes and now has one. `:feature:library` held it for the library shelf,
 * and `:app` held a second copy for the Downloads shelf — and a copy is a thing that drifts
 * one clause at a time. It already had, twice. The first drift was the font scale, and
 * `b2ededa4` fixed it in the copy rather than removing the copy; the second was still open
 * when this landed: the Downloads shelf asked for `GridCells.Adaptive`, which takes a lower
 * bound and no upper one, so a 1067 dp emulator drew 175 dp covers there while the library's
 * stopped at the 168 dp maximum. Two shelves onto one library, laying out differently.
 *
 * The copy existed because everything here was `internal` to `:feature:library`, so `:app`
 * could not call it however much it should. It lives in `:core:designsystem` now — the module
 * both of them already depend on, and where the rest of `design.md` already lives — as public
 * API. A shelf asks `rememberCoverColumns`; nobody restates the ladder. `:app`'s
 * `ShelvesAskOneRuleTest` is what holds that, because it is a property of the call sites and
 * no arithmetic test can see them.
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
 *
 * [fontScale] has no default on purpose. It had one, and the one caller that omitted it —
 * Home's continue-reading run — silently never took the accessibility step, which is the
 * same two-surfaces-disagree defect this file exists to close, one screen over. An optional
 * accessibility input on public API is a footgun with the safety off.
 */
fun coverMinimumWidth(windowWidthDp: Int, fontScale: Float): Dp {
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
fun coverMaximumWidth(fontScale: Float): Dp =
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
 * The bounds a cover shelf lays its columns out between, in this window, for this reader.
 *
 * Every shelf in the app asks this and no shelf answers it for itself — that is the whole
 * point of the function existing. The library shelf and the Downloads shelf are two views of
 * one library, and a reader who turns their text size up should not find that one of them
 * reflowed and the other did not.
 *
 * What is shared is the *rule*, not the answer. Two shelves asking this can still show
 * different column counts, and on a tablet they do: the library renders inside the list pane
 * of a `ListDetailPaneScaffold` — a measured ~340 dp of a 1067 dp window — while Downloads is
 * a single full-width surface. Same minimum, same maximum, different room to spend them in.
 *
 * The *window's* width is what is measured, rather than the shelf's own: 600 and 840 are
 * Material's window size-class breakpoints, so measuring a content pane against them would
 * read a 900 dp window behind a navigation rail as a medium one. iOS's
 * `coverMinimumWidth(shelfWidth:textSize:)` measures the shelf instead, and that — not the
 * breakpoint values — is the real divergence between the two platforms here. It is also why
 * the library pane takes the 158 dp tier a 340 dp pane has no use for; see `design.md` §4.
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
