package app.storyarc.feature.epubreader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What is over the page and is not the chrome.
 *
 * **Why these two are not a third revealed control.** `comic-reader`'s count is about what a
 * tap reveals. The return offer is armed by a long jump the reader just made and disarmed by
 * taking it; the transport exists only while a voice is speaking, and `read-aloud` requires
 * it to be reachable while the reader is looking at the page. Neither arrives with the chrome
 * and neither survives the thing that armed it — which is why they are in their own file
 * rather than in `EpubChrome.kt`, whose button count is a guarded number.
 *
 * Both sit above the foot of the page, and the return offer sits above the transport: it is
 * about where the reader just was, and the transport is about what the voice is doing now.
 */
@Composable
internal fun EpubReaderOverlays(
    /** Whether a jump has left somewhere worth going back to. */
    canReturn: Boolean,
    onReturn: () -> Unit,
    /** Whether the transport belongs on screen: speaking, or paused mid-book. */
    isReadingAloud: Boolean,
    isSpeaking: Boolean,
    onToggleReadAloud: () -> Unit,
    onSkipSentence: (Boolean) -> Unit,
    onStopReadAloud: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (!canReturn && !isReadingAloud) return

    val palette = LocalStoryArcPalette.current

    Column(
        // Clear of the two-control capsule, which sits at the very foot of the page.
        modifier = modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(bottom = StoryArcSpace.xxl * 2),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Bottom,
    ) {
        // `ebook-reader`: "a longer jump navigates with a control to return to where they
        // were". It names the page rather than saying "Back", because by the time a reader
        // notices they have lost their place they no longer remember what it was.
        if (canReturn) {
            Surface(
                shape = RoundedCornerShape(StoryArcRadius.lg),
                color = palette.surfaceRaised,
                onClick = onReturn,
                modifier = Modifier.padding(bottom = StoryArcSpace.sm),
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
    }
}
