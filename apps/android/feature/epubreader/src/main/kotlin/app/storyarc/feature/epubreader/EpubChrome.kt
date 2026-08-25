package app.storyarc.feature.epubreader

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlin.math.roundToInt

/**
 * The controls over a book.
 *
 * One tap away, and gone while reading. What it says is deliberately limited: a
 * percentage and a chapter, because `ebook-reader` forbids presenting a reflowable
 * page number as a stable identity.
 */
@Composable
internal fun EpubChrome(
    title: String,
    chapter: String?,
    progression: Double,
    failure: String?,
    isVisible: Boolean,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    if (failure != null) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .background(palette.surfaceCanvas)
                .padding(StoryArcSpace.gutter),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = failure,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
                textAlign = TextAlign.Center,
            )
        }
        return
    }

    AnimatedVisibility(visible = isVisible, enter = fadeIn(), exit = fadeOut()) {
        Column(
            modifier = modifier.fillMaxSize().safeDrawingPadding(),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            // A band, not a bare row: the chrome floats over the text, and a
            // close button drawn straight onto a paragraph is unreadable from
            // both sides.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(palette.surfaceCanvas.copy(alpha = 0.94f))
                    .padding(StoryArcSpace.md),
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(shape = CircleShape, color = palette.surfaceRaised) {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = stringResource(R.string.epub_close),
                            tint = palette.textPrimary,
                        )
                    }
                }

                Text(
                    text = chapter ?: title,
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
            }

            Box(
                modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.lg),
                contentAlignment = Alignment.Center,
            ) {
                Surface(
                    shape = RoundedCornerShape(StoryArcRadius.lg),
                    color = palette.surfaceRaised,
                ) {
                    Text(
                        // A percentage, never a page number.
                        text = stringResource(
                            R.string.epub_progress,
                            (progression * 100).roundToInt(),
                        ),
                        style = MaterialTheme.typography.labelLarge,
                        color = palette.textSecondary,
                        modifier = Modifier.padding(
                            horizontal = StoryArcSpace.md,
                            vertical = StoryArcSpace.xs,
                        ),
                    )
                }
            }
        }
    }
}
