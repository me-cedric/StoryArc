package app.storyarc.core.designsystem.navigation

import androidx.compose.material3.adaptive.Posture
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.geometry.Rect

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
