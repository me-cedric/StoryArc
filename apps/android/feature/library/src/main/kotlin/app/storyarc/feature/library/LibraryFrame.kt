package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import kotlin.math.roundToInt

/**
 * Material's compact window height, below which a window is a phone held on its side.
 * `WindowHeightSizeClass.COMPACT` is the same boundary.
 */
internal const val COMPACT_HEIGHT_DP = 480

/** Whether a window this tall has to give up chrome for the shelf. */
internal fun isCompactHeight(screenHeightDp: Int): Boolean = screenHeightDp < COMPACT_HEIGHT_DP

/**
 * How far the strip above the shelf has slid off, which is the whole of Material's
 * `enterAlways` behaviour for chrome that is not an app bar: scrolling the shelf up takes the
 * strip off first, and scrolling down brings it back before the shelf moves.
 */
@Stable
internal class HeaderCollapse {
    /** The strip's full height, set by its own layout. Not read by any composition. */
    var height = 0

    /** Zero while the strip is whole, and `-height` once it has gone. */
    var offset by mutableFloatStateOf(0f)

    val connection = object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            val next = (offset + available.y).coerceIn(-height.toFloat(), 0f)
            val used = next - offset
            offset = next
            return Offset(0f, used)
        }
    }
}

/**
 * What the library draws under its bar: the strip of notices and chips, and the shelf.
 *
 * `close-the-audited-gaps` 25.2. In a phone held on its side the title, the notice, the chips
 * and the status line took everything but about 35 dp, so the shelf drew one row and the A to Z
 * rail one letter. On a compact height the strip scrolls away with the shelf and comes back
 * when the shelf scrolls down, so the shelf and the rail get the window. On any other height
 * this is a plain column.
 */
@Composable
internal fun LibraryFrame(
    compactHeight: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable LibraryFrameScope.() -> Unit,
) {
    val collapse = remember { HeaderCollapse() }
    Column(if (compactHeight) modifier.nestedScroll(collapse.connection) else modifier) {
        LibraryFrameScope(this, collapse.takeIf { compactHeight }).content()
    }
}

internal class LibraryFrameScope(
    private val column: ColumnScope,
    private val collapse: HeaderCollapse?,
) : ColumnScope by column {

    /** The strip above the shelf. It slides off with the shelf where the frame is compact. */
    @Composable
    fun header(content: @Composable ColumnScope.() -> Unit) {
        if (collapse == null) {
            column.content()
        } else {
            Column(Modifier.collapsing(collapse)) { content() }
        }
    }
}

private fun Modifier.collapsing(collapse: HeaderCollapse): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minHeight = 0, maxHeight = Constraints.Infinity))
    collapse.height = placeable.height
    val offset = collapse.offset.roundToInt().coerceIn(-placeable.height, 0)
    layout(placeable.width, placeable.height + offset) { placeable.placeRelative(0, offset) }
}.clipToBounds()
