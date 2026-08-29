package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download

/**
 * What the queue is doing, along the foot of the screen that started it.
 *
 * One line for the download at the front and a count for the rest, because a reader browsing
 * a catalogue wants to keep browsing -- a list of six transfers belongs in Settings, not over
 * the grid they are reading. Shared by the browser and the publication detail screen: the
 * download can be started from either, and it has to be visible on the one it was started
 * from. iOS's `DownloadBanner` is the same strip.
 */
@Composable
internal fun DownloadBanner(
    download: Download,
    others: Int,
    onCancel: () -> Unit,
    onResume: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val failed = download.state as? Download.State.Failed
    val paused = download.state as? Download.State.Paused

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.surfaceRaised)
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = when {
                    failed != null -> failed.reason
                    paused != null -> stringResource(R.string.downloads_paused_title, download.title)
                    else -> stringResource(R.string.catalogue_acquire_fetching, download.title)
                },
                style = MaterialTheme.typography.bodySmall,
                color = palette.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (others > 0) {
                Text(
                    text = pluralStringResource(R.plurals.downloads_queued, others, others),
                    style = MaterialTheme.typography.labelSmall,
                    color = palette.textSecondary,
                )
            }
        }

        // One button, and which one depends on what would help. Two on a strip this size is a
        // strip nobody can hit either half of.
        if (failed != null || paused != null) {
            TextButton(onClick = onResume) { Text(stringResource(R.string.downloads_retry)) }
        } else {
            TextButton(onClick = onCancel) { Text(stringResource(R.string.downloads_stop)) }
        }
    }
}
