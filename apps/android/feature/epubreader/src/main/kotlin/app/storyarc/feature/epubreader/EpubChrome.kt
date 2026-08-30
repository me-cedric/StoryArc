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
import androidx.compose.material.icons.automirrored.filled.Toc
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.TextFormat
import androidx.compose.material.icons.outlined.BookmarkBorder
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
    isContentsReady: Boolean,
    isPageBookmarked: Boolean,
    /** Whether a jump has left somewhere worth going back to. */
    canReturn: Boolean,
    /** Whether this publication has any text a voice could say. */
    canReadAloud: Boolean,
    /** Whether the transport belongs on screen: speaking, or paused mid-book. */
    isReadingAloud: Boolean,
    isSpeaking: Boolean,
    onClose: () -> Unit,
    onReturn: () -> Unit,
    onToggleBookmark: () -> Unit,
    onOpenContents: () -> Unit,
    onOpenTheme: () -> Unit,
    onStartReadAloud: () -> Unit,
    onToggleReadAloud: () -> Unit,
    onSkipSentence: (Boolean) -> Unit,
    onStopReadAloud: () -> Unit,
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

                Surface(shape = CircleShape, color = palette.surfaceRaised) {
                    // One control, filled or not, rather than an add beside a remove:
                    // `ebook-reader` marks a *position*, and a position is either marked
                    // or it is not. The icon carries that state and the label says which
                    // way pressing it goes, so a screen reader is not left to infer it
                    // from a picture.
                    IconButton(onClick = onToggleBookmark) {
                        Icon(
                            imageVector = if (isPageBookmarked) {
                                Icons.Filled.Bookmark
                            } else {
                                Icons.Outlined.BookmarkBorder
                            },
                            contentDescription = stringResource(
                                if (isPageBookmarked) {
                                    R.string.epub_bookmark_remove
                                } else {
                                    R.string.epub_bookmark_add
                                },
                            ),
                            tint = if (isPageBookmarked) palette.accent else palette.textPrimary,
                        )
                    }
                }

                Surface(shape = CircleShape, color = palette.surfaceRaised) {
                    // Refused rather than hidden until the publication is open. A control
                    // that appears a moment after the chrome does moves the two beside it.
                    IconButton(onClick = onOpenContents, enabled = isContentsReady) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.Toc,
                            contentDescription = stringResource(R.string.epub_contents),
                            tint = if (isContentsReady) palette.textPrimary else palette.textTertiary,
                        )
                    }
                }

                Surface(shape = CircleShape, color = palette.surfaceRaised) {
                    IconButton(onClick = onOpenTheme) {
                        Icon(
                            imageVector = Icons.Filled.TextFormat,
                            contentDescription = stringResource(R.string.theme_presets),
                            tint = palette.textPrimary,
                        )
                    }
                }

                // Absent, not disabled, when the publication has no text a voice could
                // say. `ebook-reader` says a control a platform cannot honour is "absent
                // rather than empty", and this app does not ship a button that does
                // nothing.
                if (canReadAloud) {
                    Surface(shape = CircleShape, color = palette.surfaceRaised) {
                        IconButton(
                            onClick = if (isReadingAloud) onStopReadAloud else onStartReadAloud,
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.VolumeUp,
                                contentDescription = stringResource(
                                    if (isReadingAloud) {
                                        R.string.readaloud_stop
                                    } else {
                                        R.string.readaloud_start
                                    },
                                ),
                                tint = if (isReadingAloud) palette.accent else palette.textPrimary,
                            )
                        }
                    }
                }
            }

            Column(
                modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            ) {
                // `ebook-reader`: "a longer jump navigates with a control to return to
                // where they were". Above the percentage rather than in the bar at the
                // top, because it is about where the reader just was and the bar is about
                // the book -- and because it comes and goes, and a control that appeared
                // among the others would move them.
                if (canReturn) {
                    Surface(
                        shape = RoundedCornerShape(StoryArcRadius.lg),
                        color = palette.surfaceRaised,
                        onClick = onReturn,
                    ) {
                        Text(
                            text = stringResource(R.string.epub_return),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.accent,
                            modifier = Modifier.padding(
                                horizontal = StoryArcSpace.md,
                                vertical = StoryArcSpace.xs,
                            ),
                        )
                    }
                }

                if (isReadingAloud) {
                    ReadAloudBar(
                        isSpeaking = isSpeaking,
                        onPrevious = { onSkipSentence(false) },
                        onToggle = onToggleReadAloud,
                        onNext = { onSkipSentence(true) },
                        onStop = onStopReadAloud,
                    )
                }

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
