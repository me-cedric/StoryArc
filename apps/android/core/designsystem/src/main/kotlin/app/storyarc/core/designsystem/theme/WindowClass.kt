package app.storyarc.core.designsystem.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo

/**
 * How much room the window has, and therefore which navigation it asks for.
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
 * 600 dp is Material 3's medium breakpoint, where its own guidance moves a phone's
 * bottom navigation to a rail. iOS's `StoryArcWindowClass` holds the same two cases and
 * the same number in points, so the two apps change shape in the same place.
 */
enum class StoryArcWindowClass {
    /** A phone, a folded foldable, a narrow multi-window slot. One column. */
    COMPACT,

    /** Room for a navigation rail beside the content. */
    EXPANDED,
    ;

    /** Whether this window gets the persistent side navigation rather than a top bar. */
    val showsSidebar: Boolean get() = this == EXPANDED

    companion object {
        /**
         * The width, in density-independent pixels, at or above which a rail fits beside
         * a grid of covers without either of them becoming unreadable.
         */
        const val SIDEBAR_WIDTH_THRESHOLD_DP = 600

        /**
         * Which class a window of this width is.
         *
         * A width of zero is what is reported before the window has been measured, and it
         * resolves to [COMPACT]: the single-column layout fits every window and the wide
         * one does not, so the narrow answer is the safe one to be wrong with for a frame.
         */
        fun of(widthDp: Int): StoryArcWindowClass =
            if (widthDp >= SIDEBAR_WIDTH_THRESHOLD_DP) EXPANDED else COMPACT
    }
}

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
