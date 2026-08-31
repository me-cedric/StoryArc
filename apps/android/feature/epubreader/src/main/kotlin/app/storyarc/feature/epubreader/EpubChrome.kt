package app.storyarc.feature.epubreader

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.HorizontalFloatingToolbar
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * The controls over a book: a way out, a way in, and nothing else.
 *
 * `comic-reader`'s *Revealing controls* is written as a count — "exactly two controls fade in
 * over the page … no title, page number, percentage or slider is drawn over the page" — and
 * `ebook-reader` builds on the same two. It reads the same for a book as for a comic.
 *
 * **What used to be here.** Close, bookmark, contents, themes and read-aloud as five circular
 * pills in a band across the top, the chapter title between them, and a percentage at the
 * foot. Seven things, three of which were facts rather than actions. They are all still
 * reachable, one tap away, in `EpubMenuSheet.kt` — labelled in words.
 *
 * **What is deliberately still over the page, and why it is not a third control.** The
 * return-to-position offer and the read-aloud transport are in `EpubReaderOverlays.kt`, not
 * here. Neither is revealed by the tap: one is armed by a long jump the reader just made and
 * disarmed by taking it, the other exists only while a voice is speaking. The count in the
 * requirement is about what revealing the chrome puts on screen.
 *
 * **One capsule.** `HorizontalFloatingToolbar` is Material's one sanctioned floating bottom
 * capsule, for "contextual actions relevant to the body content", and it is what the comic
 * reader's chrome uses — so both readers reveal the same shape in the same place. The band
 * across the top is gone with the five pills it existed to make legible.
 *
 * `ReaderChromeTest` counts the buttons in this file. Two.
 */
@Composable
internal fun EpubChrome(
    failure: String?,
    isVisible: Boolean,
    onClose: () -> Unit,
    onOpenMenu: () -> Unit,
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

    // Over the page and under the bars, which is where "reading surfaces only" puts
    // Natural's grain: this ComposeView is a sibling above the navigator's own view, so
    // anything emitted here lands on the page. Outside the visibility below on purpose —
    // the texture belongs to the paper, and paper does not come and go with a tap. Draws
    // nothing unless Natural is on, contrast is standard, and the device is API 33 or later.
    PaperGrainOverlay()

    AnimatedVisibility(visible = isVisible, enter = fadeIn(), exit = fadeOut()) {
        Box(modifier = modifier.fillMaxSize().safeDrawingPadding()) {
            HorizontalFloatingToolbar(
                expanded = true,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(StoryArcSpace.md),
            ) {
                IconButton(onClick = onClose) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = stringResource(R.string.epub_close),
                    )
                }
                IconButton(onClick = onOpenMenu) {
                    Icon(
                        imageVector = Icons.Filled.MoreHoriz,
                        contentDescription = stringResource(R.string.epub_menu),
                    )
                }
            }
        }
    }
}
