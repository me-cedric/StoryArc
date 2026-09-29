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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import kotlinx.coroutines.launch

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
    // Answers whether the copy started. `network-share`'s offer does not disappear on a
    // `false`: the share is still down, which is the very reason the offer exists, so the
    // reader is told the attempt failed rather than left to wonder why nothing happened.
    onDownload: (suspend () -> Boolean)?,
    onLeave: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    // Above the return below, so a copy the reader started keeps going when a page turn or a
    // page that arrives ends the trouble this notice is about.
    val scope = rememberCoroutineScope()
    if (blockedSince == null) return

    val palette = LocalStoryArcPalette.current
    var now by remember(blockedSince) { mutableLongStateOf(System.currentTimeMillis()) }
    var downloadFailed by remember(blockedSince) { mutableStateOf(false) }
    var isCopying by remember(blockedSince) { mutableStateOf(false) }
    var dismissed by remember(blockedSince) { mutableStateOf<NoticeStage?>(null) }

    // A ticking clock, because the notice's whole content is a function of elapsed time and
    // nothing else changes to trigger a recomposition.
    LaunchedEffect(blockedSince) {
        while (true) {
            now = System.currentTimeMillis()
            delay(TICK_MILLIS)
        }
    }

    val stage = NoticeStage.of(blockedMillis = now - blockedSince, dismissed = dismissed) ?: return
    val isLong = stage == NoticeStage.LONG
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
            // Answers "why did nothing happen" for the one action here that can fail
            // without a page turn or a dismissal to say so on its own.
            if (downloadFailed) {
                Text(
                    text = stringResource(R.string.reader_offline_download_failed),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textPrimary,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                if (isLong && onDownload != null) {
                    TextButton(
                        enabled = !isCopying,
                        onClick = {
                            downloadFailed = false
                            isCopying = true
                            scope.launch {
                                try {
                                    downloadFailed = !onDownload()
                                } finally {
                                    isCopying = false
                                }
                            }
                        },
                    ) {
                        Text(stringResource(R.string.reader_offline_download))
                    }
                }
                if (isLong && onLeave != null) {
                    TextButton(onClick = onLeave) {
                        Text(stringResource(R.string.reader_offline_leave))
                    }
                }
                TextButton(onClick = {
                    dismissed = stage
                    onDismiss()
                }) {
                    Text(stringResource(R.string.reader_offline_dismiss))
                }
            }
        }
    }
}

/**
 * Which of the two notices the reader is owed, if either.
 *
 * Lifted beside [NetworkNotice] so a test can hold the rule. A dismissal hides the stage it
 * was made on and nothing later: the reader who dismisses the 2 s notice is still offered the
 * download at 60 s, and the reader who dismisses the offer hears nothing more until the
 * trouble ends. iOS's `NoticeStage` is the same rule.
 */
internal enum class NoticeStage {
    BRIEF,
    LONG,
    ;

    companion object {
        fun of(blockedMillis: Long, dismissed: NoticeStage?): NoticeStage? {
            val stage = when {
                blockedMillis >= OFFER_AFTER_MILLIS -> LONG
                blockedMillis >= NOTICE_AFTER_MILLIS -> BRIEF
                else -> return null
            }
            return stage.takeUnless { dismissed == LONG || dismissed == stage }
        }
    }
}

private const val TICK_MILLIS = 1_000L

/** `network-share`: "more than 2 seconds". */
private const val NOTICE_AFTER_MILLIS = 2_000L

/** `network-share`: "longer than 60 seconds". */
private const val OFFER_AFTER_MILLIS = 60_000L
