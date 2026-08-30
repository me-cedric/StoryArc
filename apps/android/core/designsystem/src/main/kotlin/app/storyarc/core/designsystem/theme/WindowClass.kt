package app.storyarc.core.designsystem.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo

/**
 * How much room the window has, and therefore which navigation and how many panes it asks
 * for.
 *
 * `native-experience` says two things that have to be answered together: a large screen
 * "uses a multi-column layout with a persistent sidebar, not a stretched phone layout",
 * and a window that is resized "reflows continuously". A third scenario adds the foldable:
 * "when an Android foldable is unfolded, folded, or half-opened, the layout follows the
 * posture". Asking what device this is answers the first and fails the other two — a
 * tablet in a third of the screen has a phone's worth of width, and a foldable is a phone
 * that becomes a tablet in the reader's hands.
 *
 * So the only input here is the width of the window, and there is no device check and no
 * posture check anywhere. Multi-window, a rotation, a fold, an unfold and a half-open
 * hinge are all the same event: the number changed. Compose recomposes on it because
 * [LocalWindowInfo] is state.
 *
 * **Five cases, not two.** Until this slice there were two, divided at 600 dp, and 600 dp
 * is Material's *medium* boundary rather than its expanded one — so a portrait tablet at
 * 800 dp and a landscape tablet at 1400 dp got the identical single-column layout, and the
 * second one wasted half its window. Material's own breakpoints are these five, they are
 * what `WindowSizeClass` reports, and they are what the pane scaffolds and the wide rail
 * are specified against.
 *
 * This is the fourth entry in the design direction's divergence register, and it is
 * deliberate: SwiftUI publishes two size classes and Material publishes five, so the two
 * apps read their own platform's answer rather than one app's answer twice.
 */
enum class StoryArcWindowClass(
    /** The narrowest window, in dp, that is of this class. */
    val lowerBoundDp: Int,
) {
    /** A phone, a folded foldable, a narrow multi-window slot. One column, one pane. */
    COMPACT(0),

    /** A portrait tablet, an unfolded foldable. One pane still, and a wider grid. */
    MEDIUM(WIDTH_MEDIUM_DP),

    /** A landscape tablet. Room for a list and a detail side by side. */
    EXPANDED(WIDTH_EXPANDED_DP),

    /** A desktop window. Two panes, and room to open the rail without taking from them. */
    LARGE(WIDTH_LARGE_DP),

    /** A very wide desktop or an external display. */
    EXTRA_LARGE(WIDTH_EXTRA_LARGE_DP),
    ;

    /**
     * Whether a list and the thing chosen from it are drawn at the same time.
     *
     * Expanded and above, which is Material's own pane rule: below it a detail is a place
     * the reader goes to, at and above it a detail is a place the reader looks at.
     */
    val showsTwoPanes: Boolean get() = this >= EXPANDED

    /**
     * Whether this window gets the persistent side navigation rather than a bottom bar.
     *
     * The same boundary as [showsTwoPanes], and deliberately so: the design direction pairs
     * them — "compact and medium: one pane, navigation bar; expanded and above: two panes
     * and an expanded rail". A rail beside a single column of covers costs the covers 96 dp
     * and buys nothing a bar was not already doing.
     *
     * Naming it separately keeps the two questions readable at their call sites, and keeps
     * one of them free to move without dragging the other with it.
     *
     * **This is also the answer the shell obeys**, rather than the one Material's
     * `navigationSuiteType` would suggest from the window on its own. Material's suggestion
     * reads the height as well as the width, so an 800 x 360 dp window — a phone in
     * landscape — was given a navigation bar while every screen that asks this question was
     * told a rail was there, and dropped the two toolbar entries the rail was supposed to be
     * carrying. Nothing could reach Shelves or Settings at that size. One answer, asked
     * once, is what makes that unexpressible.
     */
    val showsSidebar: Boolean get() = showsTwoPanes

    /**
     * Whether the rail opens already expanded.
     *
     * The reader can open and close it at any width the rail is drawn at — that is the
     * menu button's whole job. This only decides where it starts: at large and above there
     * is room for the labels *and* both panes at once, and below it the panes are worth
     * more than the labels are.
     */
    val expandsRailByDefault: Boolean get() = this >= LARGE

    companion object {
        /**
         * The width, in density-independent pixels, at or above which a second pane fits
         * beside the first — and therefore at which the rail arrives too.
         *
         * iOS divides its own two size classes at 600 pt, and keeps doing so. That is
         * divergence #4 in the design direction's register: SwiftUI publishes two size
         * classes and Material publishes five, so the number where each app changes shape is
         * its own platform's.
         */
        const val TWO_PANE_WIDTH_THRESHOLD_DP = WIDTH_EXPANDED_DP

        /**
         * Which class a window of this width is.
         *
         * A width of zero is what is reported before the window has been measured, and it
         * resolves to [COMPACT]: the single-column layout fits every window and the wide
         * ones do not, so the narrow answer is the safe one to be wrong with for a frame.
         */
        fun of(widthDp: Int): StoryArcWindowClass =
            entries.last { widthDp >= it.lowerBoundDp }
    }
}

/**
 * Material's five width breakpoints, in dp.
 *
 * Written here rather than read from `WindowSizeClass`'s constants so that [of] stays a
 * pure function of an integer and the whole ladder can be asserted on a plain JVM, which
 * is the only place this repository has a test loop. They are asserted against
 * `WindowSizeClass`'s own constants in `WindowClassTest`, so a Material breakpoint that
 * moved would fail rather than drift.
 */
private const val WIDTH_MEDIUM_DP = 600
private const val WIDTH_EXPANDED_DP = 840
private const val WIDTH_LARGE_DP = 1200
private const val WIDTH_EXTRA_LARGE_DP = 1600

/**
 * The class of the window this composition is in.
 *
 * Read from [LocalWindowInfo] rather than from the configuration: the container size is
 * the window the app actually occupies, which is the thing that changes when a foldable
 * opens or a reader drags a multi-window divider. The activity declares those as
 * configuration changes it handles itself, so nothing is recreated and nothing is lost —
 * the composition simply reads a new number.
 */
@Composable
fun rememberWindowClass(): StoryArcWindowClass {
    val density = LocalDensity.current
    val size = LocalWindowInfo.current.containerSize
    return remember(density, size) {
        StoryArcWindowClass.of(with(density) { size.width.toDp() }.value.toInt())
    }
}
