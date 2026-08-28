package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import java.util.UUID

/**
 * What is on the device, what it weighs, and how to get rid of it.
 *
 * `offline-downloads` asks for a storage view showing "total space used ... broken down by
 * source and by the largest publications", where "each row can be removed individually".
 * This is the first cut of that: the total, the rows, and removal. iOS's `DownloadsSettings`
 * is the same screen.
 */
@Composable
fun DownloadsGroup(
    library: DownloadLibrary,
    /**
     * What the files actually weigh. Asked of the filesystem by the caller, because the
     * system can reclaim a download and a total that counts bytes nobody has is the kind of
     * number that makes a reader distrust the whole screen.
     */
    bytesOnDisk: Long,
    /** The name of the source a download came from, when it came from one. */
    sourceName: (UUID) -> String?,
    onRemove: (Download) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    var removing by remember { mutableStateOf<Download?>(null) }

    // Largest first, which is the order the question "what can I delete" is asked in.
    val finished = library.finished.sortedByDescending { it.downloadedBytes }

    if (finished.isEmpty() && library.pending.isEmpty()) {
        Text(
            text = stringResource(R.string.downloads_none),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
        return
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = stringResource(R.string.downloads_total),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
        )
        Text(
            text = android.text.format.Formatter.formatShortFileSize(
                androidx.compose.ui.platform.LocalContext.current,
                bytesOnDisk,
            ),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
        )
    }

    if (library.pending.isNotEmpty()) {
        Text(
            text = stringResource(R.string.downloads_pending),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
        library.pending.forEach { download -> PendingRow(download) }
    }

    if (finished.isNotEmpty()) {
        Text(
            text = stringResource(R.string.downloads_on_device),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
        finished.forEach { download ->
            FinishedRow(download, sourceName) { removing = download }
        }
    }

    // Confirmed, because it deletes bytes. `offline-downloads` says the app "never deletes a
    // download without asking", and although that sentence is about the low-storage case, a
    // reader's own tap deserves the same courtesy.
    removing?.let { download ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.downloads_remove_title)) },
            text = { Text(stringResource(R.string.downloads_remove_body, download.title)) },
            confirmButton = {
                TextButton(onClick = {
                    onRemove(download)
                    removing = null
                }) {
                    Text(stringResource(R.string.downloads_remove))
                }
            },
            dismissButton = {
                TextButton(onClick = { removing = null }) {
                    Text(stringResource(R.string.downloads_cancel))
                }
            },
        )
    }
}

@Composable
private fun FinishedRow(
    download: Download,
    sourceName: (UUID) -> String?,
    onRemove: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val size = android.text.format.Formatter.formatShortFileSize(context, download.downloadedBytes)
    val source = download.sourceId?.let(sourceName)

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = download.title,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = if (source != null) "$source · $size" else size,
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                imageVector = Icons.Filled.Delete,
                contentDescription = stringResource(
                    R.string.downloads_remove_action,
                    download.title,
                ),
                tint = palette.textSecondary,
            )
        }
    }
}

@Composable
private fun PendingRow(download: Download) {
    val palette = LocalStoryArcPalette.current
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier.fillMaxWidth().padding(vertical = StoryArcSpace.xs),
    ) {
        Text(
            text = download.title,
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
        )
        when (val state = download.state) {
            is Download.State.Failed -> Text(
                // The reason, in the reader's words, and how many times it was tried.
                // `offline-downloads` requires "a plain-language reason and a retry action";
                // the retry is not built yet, which is why the count is shown rather than
                // hidden behind a button that does not exist.
                text = stringResource(
                    R.string.downloads_failed,
                    state.reason,
                    state.attempts,
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
            is Download.State.Paused -> Text(
                text = stringResource(state.reason.explanationRes),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
            else -> {
                val fraction = download.fraction
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { fraction.toFloat() },
                        modifier = Modifier.fillMaxWidth(),
                    )
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

/** Why this one is not moving, in the reader's terms. */
private val Download.Pause.explanationRes: Int
    get() = when (this) {
        Download.Pause.BY_READER -> R.string.downloads_paused_by_reader
        Download.Pause.WAITING_FOR_WIFI -> R.string.downloads_paused_waiting_for_wifi
        Download.Pause.OUT_OF_SPACE -> R.string.downloads_paused_out_of_space
    }
