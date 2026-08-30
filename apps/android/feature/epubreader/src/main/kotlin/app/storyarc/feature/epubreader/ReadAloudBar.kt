package app.storyarc.feature.epubreader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * The transport, on screen only while a book is being read aloud.
 *
 * Four controls and no scrubber. `ebook-reader` asks the *lock screen* for "play, pause,
 * and sentence skip", and the reader looking at the page gets the same three plus a stop —
 * because the way out of speech is not obvious from a pause button, and a reader who is
 * done listening should not have to guess.
 *
 * It sits where the return control does, above the percentage, and for the same reason: it
 * comes and goes, and a control that appeared among the ones at the top would move them.
 *
 * iOS's `ReadAloudBar` is the same five decisions in SwiftUI.
 */
@Composable
internal fun ReadAloudBar(
    isSpeaking: Boolean,
    onPrevious: () -> Unit,
    onToggle: () -> Unit,
    onNext: () -> Unit,
    onStop: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(StoryArcRadius.lg),
        color = palette.surfaceRaised,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = StoryArcSpace.xs),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Control(
                Icons.Filled.SkipPrevious,
                R.string.readaloud_previous,
                palette.textPrimary,
                onPrevious,
            )
            Control(
                if (isSpeaking) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                if (isSpeaking) R.string.readaloud_pause else R.string.readaloud_play,
                palette.accent,
                onToggle,
            )
            Control(Icons.Filled.SkipNext, R.string.readaloud_next, palette.textPrimary, onNext)
            Control(Icons.Filled.Stop, R.string.readaloud_stop, palette.textPrimary, onStop)
        }
    }
}

@Composable
private fun Control(
    icon: ImageVector,
    label: Int,
    tint: Color,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick) {
        Icon(imageVector = icon, contentDescription = stringResource(label), tint = tint)
    }
}
