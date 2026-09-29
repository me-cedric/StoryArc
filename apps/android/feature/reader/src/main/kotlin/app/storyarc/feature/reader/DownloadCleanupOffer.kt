package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What the end screen offers about this publication's download.
 *
 * Decision D7. `null` for most publications: `offline-downloads` sweeps a *download*,
 * and a publication opened from a folder or read from a share was never one. Both
 * actions take effect when the reader closes, so the undo shows where the reader is.
 */
data class DownloadCleanupOffer(
    /**
     * Whether this download goes when the reader closes: the automatic sweep is on and
     * the reader has not kept it, or the reader asked for it here. A function, read when
     * the end screen shows, so a choice made on an earlier visit to it is not lost.
     */
    val isRemovedOnClose: () -> Boolean,
    /** "Remove download": the download goes when the reader closes, with the sweep's undo. */
    val onRemove: () -> Unit,
    /** "Keep": the sweep skips this download from now on. */
    val onKeep: () -> Unit,
)

/**
 * What the end screen shows about the download, from whether there is one to offer
 * anything about at all. iOS's `DownloadCleanupPresentation` is the same table.
 */
internal enum class DownloadCleanupPresentation {
    /** No offer at all — most publications were never a download. */
    NONE,

    /** The download stays: an action to have it removed when the reader closes. */
    OFFER_REMOVAL,

    /** The download goes when the reader closes: a sentence saying so, and Keep. */
    STATE_AND_OFFER_KEEP,
    ;

    companion object {
        /**
         * Lifted out of the composable so `DownloadCleanupPresentationTest` can drive it
         * with a plain value. [choice] is the reader's tap on this screen — true for
         * "Remove download", false for "Keep" — which answers at once.
         */
        fun resolved(offer: DownloadCleanupOffer?, choice: Boolean? = null): DownloadCleanupPresentation = when {
            offer == null -> NONE
            choice ?: offer.isRemovedOnClose() -> STATE_AND_OFFER_KEEP
            else -> OFFER_REMOVAL
        }
    }
}

/**
 * D7's row on the end screen: an action to remove the download when the reader closes,
 * or — when that is already due — a sentence saying so and an action to keep this one.
 */
@Composable
internal fun DownloadCleanupRow(offer: DownloadCleanupOffer?) {
    if (offer == null) return
    // The reader's tap on this screen, so the row answers it at once.
    var choice by remember { mutableStateOf<Boolean?>(null) }
    // White, not the theme's accent: this overlay is near-black whatever the app's
    // appearance, and the accent on it fails contrast.
    val labels = ButtonDefaults.textButtonColors(contentColor = Color.White)
    when (DownloadCleanupPresentation.resolved(offer, choice)) {
        DownloadCleanupPresentation.NONE -> Unit
        DownloadCleanupPresentation.OFFER_REMOVAL -> TextButton(
            onClick = {
                offer.onRemove()
                choice = true
            },
            colors = labels,
        ) {
            Text(stringResource(R.string.reader_end_remove_download))
        }
        DownloadCleanupPresentation.STATE_AND_OFFER_KEEP -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            Text(
                text = stringResource(R.string.reader_end_download_will_be_removed),
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.7f),
            )
            TextButton(
                onClick = {
                    offer.onKeep()
                    choice = false
                },
                colors = labels,
            ) {
                Text(stringResource(R.string.reader_end_keep_download))
            }
        }
    }
}
