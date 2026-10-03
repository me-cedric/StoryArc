package app.storyarc.feature.epubreader

import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.separatingVerticalHingeBounds
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalWindowInfo
import app.storyarc.core.designsystem.navigation.HingeSpreadSplit
import app.storyarc.core.designsystem.navigation.hingeInset
import app.storyarc.core.designsystem.navigation.hingeSpreadSplit
import kotlin.math.roundToInt

/**
 * Keeping the EPUB navigator's own page off a vertical hinge.
 *
 * `native-experience` 19.5's other half: `feature/reader` splits a comic spread at the
 * hinge, or insets a lone page around it, because it draws every page itself. This reader
 * does not — Readium's `EpubNavigatorFragment` decides a fixed-layout spread's own two
 * leaves, and a reflowable book has no "page" at all until the width it is handed reflows
 * one. So the one thing this app can still do is keep the whole navigator off the hinge,
 * whichever kind of page it goes on to draw inside that width: [hingeInset] is the exact
 * rule `feature/reader` uses for a lone page, asked here of the navigator's own container
 * rather than of one decoded bitmap.
 *
 * [EpubHingeLayout] is deliberately not `android.widget.FrameLayout.LayoutParams` — a plain
 * value, so `EpubHingeLayoutTest` asserts it without Robolectric. [asLayoutParams] is the
 * one line that turns it into the real thing, and is not itself tested for the reason
 * `DetailAbsencesTests.swift`'s own comment gives: it is arithmetic-free.
 */
enum class HingeEdge { START, END, NONE }

data class EpubHingeLayout(
    /** `null` means match the parent — there is nothing to avoid. */
    val widthPx: Int?,
    val edge: HingeEdge,
)

/** [EpubHingeLayout] for a navigator drawing inside a container split by [split]. */
fun epubHingeLayout(split: HingeSpreadSplit): EpubHingeLayout {
    val inset = hingeInset(split) ?: return EpubHingeLayout(widthPx = null, edge = HingeEdge.NONE)
    return EpubHingeLayout(
        widthPx = inset.width.roundToInt(),
        edge = if (inset.atStart) HingeEdge.START else HingeEdge.END,
    )
}

/** [EpubHingeLayout] as the `FrameLayout.LayoutParams` a navigator view actually takes. */
fun EpubHingeLayout.asLayoutParams(): FrameLayout.LayoutParams =
    FrameLayout.LayoutParams(widthPx ?: FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT).apply {
        gravity = when (edge) {
            HingeEdge.START -> Gravity.START
            HingeEdge.END -> Gravity.END
            HingeEdge.NONE -> Gravity.NO_GRAVITY
        }
    }

/**
 * Sets [container]'s layout params from the window's separating vertical hinge, again on each
 * fold or resize.
 *
 * [container] fills the window at the window's origin, so the window width and the hinge
 * bounds are already in its own coordinates.
 */
@Composable
internal fun KeepOffHinge(container: View) {
    val hinge = currentWindowAdaptiveInfoV2().windowPosture.separatingVerticalHingeBounds.firstOrNull()
    val width = LocalWindowInfo.current.containerSize.width
    LaunchedEffect(hinge, width) {
        container.layoutParams = epubHingeLayout(hingeSpreadSplit(width.toFloat(), hinge?.left, hinge?.right))
            .asLayoutParams()
        container.requestLayout()
    }
}
