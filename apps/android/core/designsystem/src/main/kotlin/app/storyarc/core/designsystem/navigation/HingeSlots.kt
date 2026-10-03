package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.separatingVerticalHingeBounds
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity

/**
 * A separating vertical hinge in a page surface's own coordinates, in pixels.
 *
 * `native-experience`, *Foldables*: the reader keeps a page's focal area off the hinge.
 * [hingeSpreadSplit] and [hingeInset] hold the arithmetic. This file applies it to a page.
 */
data class SurfaceHinge(val start: Float, val end: Float)

/**
 * Where a page surface sits in the window.
 *
 * Apply [modifier] to the surface that holds the pages, not to a page. A page in a pager or a
 * list moves with each frame of a swipe. A hinge measured from that edge splits the page again
 * on each frame, and recomposes each page on each frame on every device.
 */
@Stable
class HingeSurface {
    private var left by mutableFloatStateOf(0f)

    /** Records the surface's left edge in the window. */
    val modifier: Modifier = Modifier.onGloballyPositioned { left = it.positionInWindow().x }

    /** The window's separating vertical hinge in this surface's coordinates, or `null`. */
    val hinge: SurfaceHinge?
        @Composable get() = currentWindowAdaptiveInfoV2().windowPosture.separatingVerticalHingeBounds
            .firstOrNull()?.let { SurfaceHinge(it.left - left, it.right - left) }
}

@Composable
fun rememberHingeSurface(): HingeSurface = remember { HingeSurface() }

/**
 * One page, moved to the wider side of [hinge] at that side's width.
 *
 * With no hinge, [content] draws exactly as it did before 19.5. A container of unbounded width
 * (a horizontal strip) also draws [content] unchanged: each page in a strip crosses the hinge in
 * turn, so there is no side to move it to.
 */
@Composable
fun HingeInsetPage(hinge: SurfaceHinge?, content: @Composable () -> Unit) {
    if (hinge == null) {
        content()
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val inset = if (constraints.hasBoundedWidth) {
            hingeInset(hingeSpreadSplit(constraints.maxWidth.toFloat(), hinge.start, hinge.end))
        } else {
            null
        }
        val modifier = if (inset == null) {
            Modifier.fillMaxSize()
        } else {
            Modifier
                .align(if (inset.atStart) Alignment.CenterStart else Alignment.CenterEnd)
                .width(with(LocalDensity.current) { inset.width.toDp() })
                .fillMaxHeight()
        }
        Box(modifier, contentAlignment = Alignment.Center) { content() }
    }
}

/**
 * Two facing pages: equal halves, or the two sides of [hinge] with the hinge's own width
 * between them. [half] draws the page at screen position 0 (left) or 1 (right).
 */
@Composable
fun HingeSpread(hinge: SurfaceHinge?, half: @Composable (Int) -> Unit) {
    if (hinge == null) {
        Row(Modifier.fillMaxSize()) {
            repeat(2) { Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) { half(it) } }
        }
        return
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val split = hingeSpreadSplit(constraints.maxWidth.toFloat(), hinge.start, hinge.end)
        val density = LocalDensity.current
        Row(Modifier.fillMaxSize()) {
            repeat(2) { index ->
                if (index == 1) Spacer(Modifier.width(with(density) { split.gap.toDp() }))
                val width = if (index == 0) split.leadingWidth else split.trailingWidth
                Box(
                    Modifier.width(with(density) { width.toDp() }).fillMaxHeight(),
                    contentAlignment = Alignment.Center,
                ) { half(index) }
            }
        }
    }
}
