package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import kotlinx.coroutines.delay

/**
 * What the reader says when the network has gone quiet.
 *
 * `network-share` is precise about the timing: an indicator appears "only if a page is
 * actually blocked on the network for more than 2 seconds", and after 60 seconds of failure
 * the app "offers to download the current publication for offline reading [...] and to
 * return to the library". A brief stall says nothing, because a brief stall is not news.
 *
 * The reader knows nothing about SMB. It is handed the moment trouble started and decides
 * what to show; the app layer is what reads that moment from whichever source produced it.
 */
@Composable
fun NetworkNotice(
    blockedSince: Long?,
    onDismiss: () -> Unit,
    onDownload: (() -> Unit)?,
    onLeave: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    if (blockedSince == null) return

    val palette = LocalStoryArcPalette.current
    var now by remember(blockedSince) { mutableLongStateOf(System.currentTimeMillis()) }

    // A ticking clock, because the notice's whole content is a function of elapsed time and
    // nothing else changes to trigger a recomposition.
    LaunchedEffect(blockedSince) {
        while (true) {
            now = System.currentTimeMillis()
            delay(TICK_MILLIS)
        }
    }

    val blocked = now - blockedSince
    if (blocked < NOTICE_AFTER_MILLIS) return

    val isLong = blocked >= OFFER_AFTER_MILLIS
    val message = stringResource(
        if (isLong) R.string.reader_offline_long else R.string.reader_offline_brief,
    )

    Surface(
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.md),
        modifier = modifier
            .fillMaxWidth()
            .padding(StoryArcSpace.gutter)
            .semantics {
                liveRegion = LiveRegionMode.Polite
                contentDescription = message
            },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
            modifier = Modifier.padding(StoryArcSpace.md),
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                if (isLong && onDownload != null) {
                    TextButton(onClick = onDownload) {
                        Text(stringResource(R.string.reader_offline_download))
                    }
                }
                if (isLong && onLeave != null) {
                    TextButton(onClick = onLeave) {
                        Text(stringResource(R.string.reader_offline_leave))
                    }
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.reader_offline_dismiss))
                }
            }
        }
    }
}

private const val TICK_MILLIS = 1_000L

/** `network-share`: "more than 2 seconds". */
private const val NOTICE_AFTER_MILLIS = 2_000L

/** `network-share`: "longer than 60 seconds". */
private const val OFFER_AFTER_MILLIS = 60_000L
