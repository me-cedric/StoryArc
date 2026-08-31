package app.storyarc.core.designsystem.grid

import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp

/**
 * As many columns as fit at [minSize], none of them wider than [maxSize].
 *
 * `library-browsing`'s Adaptive-columns scenario has two clauses, and Compose's own
 * [GridCells.Adaptive] answers one of them: "the number of grid columns follows the
 * available width, **and cover size stays within the readable range defined in the design
 * tokens**". `Adaptive` takes a minimum and no maximum, so on a narrow window — a phone in
 * portrait, a foldable folded, a freeform window dragged small — one column stretches to
 * whatever is left, and a single cover fills the screen edge to edge.
 *
 * SwiftUI's `GridItem(.adaptive(minimum:maximum:))` takes both bounds, which is why iOS
 * held the second clause and Android did not. This is that value, and nothing more: below
 * the cap it computes exactly what [GridCells.Adaptive] computes, remainder pixels
 * included, so a wide window is laid out identically to before.
 *
 * Public, and reached through [rememberCoverColumns] rather than constructed: every shelf in
 * the app is entitled to the same column rule, and the Downloads shelf was drawing plain
 * [GridCells.Adaptive] for the whole time this class was `internal` to `:feature:library`.
 */
class BoundedAdaptive(
    private val minSize: Dp,
    private val maxSize: Dp,
) : GridCells {

    override fun Density.calculateCrossAxisCellSizes(
        availableSize: Int,
        spacing: Int,
    ): List<Int> {
        val minimum = minSize.roundToPx()
        val maximum = maxSize.roundToPx()
        // At least one column, however narrow the window: a grid with no columns shows
        // nothing, which is worse than a cover that is too wide.
        val count = maxOf(1, (availableSize + spacing) / (minimum + spacing))
        val gridSize = availableSize - spacing * (count - 1)
        val slotSize = gridSize / count
        // Capped: the columns keep the readable width and the leftover stays leftover,
        // rather than being poured into the covers. At the maximum exactly, not past it —
        // the remainder below hands a spare pixel to the leading columns, and a slot
        // already at the cap would be pushed one past it.
        if (slotSize >= maximum) return List(count) { maximum }
        // Uncapped: the division's remainder is spread one pixel at a time across the
        // leading columns, so the row ends exactly where the window does.
        val remainder = gridSize % count
        return List(count) { index -> slotSize + if (index < remainder) 1 else 0 }
    }

    // Compose compares the value it was given last composition against this one to decide
    // whether the grid has to be measured again. Identity comparison would say "changed"
    // on every recomposition.
    override fun equals(other: Any?): Boolean =
        other is BoundedAdaptive && other.minSize == minSize && other.maxSize == maxSize

    override fun hashCode(): Int = 31 * minSize.hashCode() + maxSize.hashCode()
}
