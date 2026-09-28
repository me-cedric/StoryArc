package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What the end screen offers about this publication's download.
 *
 * Decision D7. `null` for most publications: `offline-downloads` sweeps a *download*,
 * and a publication opened from a folder or read from a share was never one.
 */
data class DownloadCleanupOffer(
    /**
     * Whether the automatic sweep is on for this device. On: the end screen states
     * that the download goes when the reader closes, with [onKeep] to stop that.
     * Off: the end screen offers [onRemove] instead -- the sweep will not do it.
     */
    val automaticCleanupIsOn: Boolean,
    val onRemove: () -> Unit,
    val onKeep: () -> Unit,
)

/**
 * What the end screen shows about the download, from whether there is one to offer
 * anything about at all. iOS's `DownloadCleanupPresentation` is the same table.
 */
internal enum class DownloadCleanupPresentation {
    /** No offer at all -- most publications were never a download. */
    NONE,

    /** The sweep is off: an action to remove the download now. */
    OFFER_REMOVAL,

    /** The sweep is on: a sentence saying so, and an action to keep this one anyway. */
    STATE_AND_OFFER_KEEP,
    ;

    companion object {
        /** Lifted out of the view, so `DownloadCleanupPresentationTest` can drive it
         * with a plain nullable rather than a screen. */
        fun resolved(offer: DownloadCleanupOffer?): DownloadCleanupPresentation = when {
            offer == null -> NONE
            offer.automaticCleanupIsOn -> STATE_AND_OFFER_KEEP
            else -> OFFER_REMOVAL
        }
    }
}

/**
 * D7: an action to remove the download, or — with the sweep already doing that — a
 * sentence saying so and an action to keep this one instead.
 */
@Composable
internal fun DownloadCleanupRow(offer: DownloadCleanupOffer?) {
    if (offer == null) return
    // White, not the theme's accent: this overlay is near-black whatever the app's
    // appearance, and the accent on it fails contrast.
    val labels = ButtonDefaults.textButtonColors(contentColor = Color.White)
    when (DownloadCleanupPresentation.resolved(offer)) {
        DownloadCleanupPresentation.NONE -> Unit
        DownloadCleanupPresentation.OFFER_REMOVAL -> TextButton(onClick = offer.onRemove, colors = labels) {
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
            TextButton(onClick = offer.onKeep, colors = labels) {
                Text(stringResource(R.string.reader_end_keep_download))
            }
        }
    }
}
