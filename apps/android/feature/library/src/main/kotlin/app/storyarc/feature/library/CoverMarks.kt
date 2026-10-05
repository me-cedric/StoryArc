package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import androidx.compose.ui.unit.dp

/**
 * The two marks a cover in the grid or the list carries in its corners.
 *
 * Split out of `CoverGrid.kt` at the 800-line cap: both of these are drawing primitives the
 * grid and the list share, asked for by neither's own business, which is the real seam the
 * cap found. `pnpm lines:check` is what asked for the split, not a change in what either
 * mark does.
 */

/**
 * Whether a cover is one of the ones the reader has picked.
 *
 * A mark in the corner rather than a tint over the artwork: the artwork is the interface, and
 * a wash of accent colour across a cover hides the one thing the reader is using to tell it
 * from its neighbour.
 *
 * iOS's `PickMark` sits in the same corner.
 *
 * `library-browsing` lets a cover carry "at most two marks: how far the reader has got, and
 * whether it can be read with no network", and forbids a third "for any reason". This grid
 * spends one on the progress rail and has no downloaded mark yet, so the tick fits. Whoever
 * draws that mark here inherits iOS's rule with it: while the reader is picking, the pick
 * mark takes the downloaded mark's place rather than joining it.
 */
@Composable
internal fun PickMark(isPicked: Boolean, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Icon(
        imageVector = if (isPicked) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
        // Announced by the cell, which already speaks the title this belongs to.
        contentDescription = null,
        tint = if (isPicked) MaterialTheme.colorScheme.primary else palette.textTertiary,
        modifier = modifier.padding(StoryArcSpace.xs),
    )
}

/**
 * Whether this cover can be read with no network, said in one corner.
 *
 * `design.md` asks for "downloaded state as a small filled mark in one corner", and the
 * palette calls `status/downloaded` "the one badge permitted to compete with cover art".
 * That is the other question a shelf is asked besides how far in the reader got — can I read
 * this on the train — and it is the axis the library's own scope control is built on, so it
 * had better be visible on the covers.
 *
 * Filled, on its own ground, and the only status colour in the grid. A glyph on a disc reads
 * over any artwork; an unfilled one is a shape lost in whatever the cover happens to be. The
 * disc takes `surfaceCanvas` so the mark is legible in both appearances without a shadow.
 *
 * It stands down while the reader is picking — see the call site, and iOS's
 * `CoverCell.showsOnDeviceMark` for the same rule stated as a property.
 *
 * No description: the cell speaks this in its own label, and a second announcement would
 * make one cover two stops for a screen reader.
 */
@Composable
internal fun OnDeviceMark(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Box(
        modifier = modifier.padding(StoryArcSpace.xs),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(ON_DEVICE_MARK_SIZE)
                .clip(CircleShape)
                .background(palette.surfaceCanvas),
        )
        Icon(
            imageVector = Icons.Filled.CheckCircle,
            contentDescription = null,
            tint = StoryArcColor.Status.downloaded,
            modifier = Modifier.size(ON_DEVICE_MARK_SIZE),
        )
    }
}

/** Large enough to read over artwork, small enough not to be a second thing on the cover. */
internal val ON_DEVICE_MARK_SIZE = 18.dp
