package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * A publication the reader has finished.
 *
 * The owner's field report on v0.1.1: "the finished indicator could be more prominent" — a
 * full-width rail in the rail's own muted tone was the only sign, and a full bar reads as
 * decoration rather than as news.
 *
 * Material 3's own badge shape — a filled disc in `primaryContainer` with its
 * `onPrimaryContainer` icon — rather than [OnDeviceMark]'s bespoke one, so the two glyphs
 * that can share a cover in different states read as two different kinds of fact: this one a
 * status the theme itself carries, that one this app's one accent colour for a download.
 * iOS's `FinishedMark` draws the same glyph in the system material for the same reason:
 * legible over a cover of any tone, light or dark.
 *
 * Kept out of `CoverGrid.kt`, which is already at the line cap this project enforces: a badge
 * two call sites share belongs beside neither of them alone.
 *
 * No description: the cell speaks this in its own label — see `spokenCellLabel`'s `finished`
 * parameter — and a second announcement would make one cover two stops for TalkBack.
 */
@Composable
internal fun FinishedMark(modifier: Modifier = Modifier) {
    val colorScheme = MaterialTheme.colorScheme
    Box(
        modifier = modifier
            .padding(StoryArcSpace.xs)
            .size(ON_DEVICE_MARK_SIZE)
            .clip(CircleShape)
            .background(colorScheme.primaryContainer),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.Check,
            contentDescription = null,
            tint = colorScheme.onPrimaryContainer,
            modifier = Modifier.size(ON_DEVICE_MARK_SIZE * 0.65f),
        )
    }
}
