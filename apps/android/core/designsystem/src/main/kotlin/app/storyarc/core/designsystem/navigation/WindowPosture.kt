package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.material3.adaptive.Posture
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo

/**
 * The reader's layout for the posture of a foldable device.
 *
 * `native-experience`, *Half-open on a table* (D3) and *Held like a book* (D4). The decision
 * reads only the posture, so `WindowPostureTest` asserts it on the JVM without a device.
 */
enum class ReaderPosture {
    /** No fold, a fold that is flat, or no posture at all: the layout of a flat display. */
    FLAT,

    /** Half open with a horizontal fold: the page above the fold, the controls below it. */
    TABLETOP,

    /** Half open with a vertical fold: a spread, one page on each half. */
    BOOK,
    ;

    companion object {
        /** The layout for [posture]. A `null` posture is a device that reports none (2.7). */
        fun of(posture: Posture?): ReaderPosture {
            val fold = posture?.hingeList?.firstOrNull { !it.isFlat } ?: return FLAT
            return if (fold.isVertical) BOOK else TABLETOP
        }
    }
}

/**
 * A posture that a test supplies instead of the window's own.
 *
 * `null` in the app. Robolectric has no folding feature, so a snapshot of tabletop or book
 * posture provides one here.
 */
val LocalPostureOverride = staticCompositionLocalOf<Posture?> { null }

/** The window's posture, or the one a test provides through [LocalPostureOverride]. */
@Composable
fun currentPosture(): Posture = LocalPostureOverride.current ?: currentWindowAdaptiveInfoV2().windowPosture

/**
 * The vertical fold that a page and a control keep off, in window pixels, or `null`.
 *
 * A fold that separates the display or occludes part of it (1.4). A fold with no width is made
 * one pixel wide: a Pixel Fold that is half open reports its fold as a line, and the line still
 * divides the display in two.
 */
fun Posture.avoidedVerticalFold(): Rect? =
    hingeList.firstOrNull { it.isVertical && (it.isSeparating || it.isOccluding) }?.bounds
        ?.let { it.copy(right = maxOf(it.right, it.left + 1f)) }

/** The horizontal fold of tabletop posture, in window pixels, or `null`. One pixel high at least. */
fun Posture.tabletopFold(): Rect? =
    hingeList.firstOrNull { !it.isVertical && !it.isFlat }?.bounds
        ?.let { it.copy(bottom = maxOf(it.bottom, it.top + 1f)) }

/**
 * The window's vertical fold as a [SurfaceHinge], for a surface that fills the window from its
 * origin, such as the EPUB reader's controls over its navigator.
 */
val Posture.windowHinge: SurfaceHinge?
    get() = avoidedVerticalFold()?.let { SurfaceHinge(it.left, it.right) }

/** The margins, in window pixels, that keep a bottom sheet off the fold. See [sheetOffFold]. */
data class SheetMargins(val left: Float = 0f, val right: Float = 0f, val top: Float = 0f)

/**
 * Where a bottom sheet goes on a window [windowWidth] pixels wide (1.4, D3).
 *
 * A vertical fold: the wider side, as a lone page does. Tabletop posture: below the fold, on the
 * flat half. Otherwise the sheet keeps its usual place.
 */
fun Posture.sheetMargins(windowWidth: Float): SheetMargins {
    val top = tabletopFold()?.takeIf { ReaderPosture.of(this) == ReaderPosture.TABLETOP }?.bottom ?: 0f
    val fold = avoidedVerticalFold() ?: return SheetMargins(top = top)
    val side = hingeInset(hingeSpreadSplit(windowWidth, fold.left, fold.right)) ?: return SheetMargins(top = top)
    val rest = windowWidth - side.width
    return if (side.atStart) SheetMargins(right = rest, top = top) else SheetMargins(left = rest, top = top)
}

/**
 * The `modifier` for a `ModalBottomSheet` that keeps it off the fold. See [sheetMargins].
 *
 * Margins and not a size: the sheet measures its drag anchors from the height it is given, so a
 * capped height puts the sheet at the top of the window. The sheet's window covers the app's
 * window, so the fold's window coordinates are its own.
 */
@Composable
fun sheetOffFold(): Modifier {
    val margins = currentPosture().sheetMargins(LocalWindowInfo.current.containerSize.width.toFloat())
    return with(LocalDensity.current) {
        Modifier.absolutePadding(left = margins.left.toDp(), right = margins.right.toDp(), top = margins.top.toDp())
    }
}
