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
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Switch
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.ImportedCopies
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
// Internal like every other group on this screen, and like iOS's `DownloadsSettings`. It
// was the one public composable here, which nothing outside the module ever called.
internal fun DownloadsGroup(
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
    /**
     * Moves a queued download one place. `offline-downloads` asks for reorder among the
     * queue's own controls, and one place at a time is reachable without a drag gesture.
     */
    onReorder: (Download, Boolean) -> Unit = { _, _ -> },
    /** The reader's own policy for the queue, and how to change it. */
    settings: AppSettings = AppSettings.Defaults,
    onChange: (AppSettings) -> Unit = {},
    /** The row a search result pointed at, if the reader arrived through one. */
    highlight: SettingsAnchor? = null,
) {
    val palette = LocalStoryArcPalette.current
    var removing by remember { mutableStateOf<Download?>(null) }

    // Largest first, which is the order the question "what can I delete" is asked in.
    val finished = library.finished.sortedByDescending { it.downloadedBytes }

    Policy(settings, onChange, highlight)

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
        library.pending.forEach { download ->
            PendingRow(
                download = download,
                // Only a queued download has an order to change: a running one has started
                // and the list is short enough that its ends are obvious.
                canReorder = download.state == Download.State.Queued,
                onReorder = { later -> onReorder(download, later) },
            )
        }
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
            text = {
                // `local-library` asks for more of this sentence than a download needs.
                // Deleting an imported copy "confirms, naming the title and the space to be
                // freed, and states that the original file elsewhere is untouched" -- the
                // last clause because an import is the one row on this screen that has an
                // original somewhere, and a reader must not have to guess whether the app is
                // about to reach outside itself.
                Text(
                    if (ImportedCopies.isImported(download)) {
                        stringResource(
                            R.string.downloads_remove_body_imported,
                            download.title,
                            android.text.format.Formatter.formatShortFileSize(
                                androidx.compose.ui.platform.LocalContext.current,
                                download.downloadedBytes,
                            ),
                        )
                    } else {
                        stringResource(R.string.downloads_remove_body, download.title)
                    },
                )
            },
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
private fun PendingRow(
    download: Download,
    canReorder: Boolean,
    onReorder: (Boolean) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier.fillMaxWidth().padding(vertical = StoryArcSpace.xs),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = download.title,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            if (canReorder) {
                IconButton(onClick = { onReorder(false) }) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowUp,
                        contentDescription = stringResource(
                            R.string.downloads_move_earlier,
                            download.title,
                        ),
                        tint = palette.textSecondary,
                    )
                }
                IconButton(onClick = { onReorder(true) }) {
                    Icon(
                        imageVector = Icons.Filled.KeyboardArrowDown,
                        contentDescription = stringResource(
                            R.string.downloads_move_later,
                            download.title,
                        ),
                        tint = palette.textSecondary,
                    )
                }
            }
        }
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

/**
 * What the reader has asked of the queue.
 *
 * The three `offline-downloads` calls policy: whether to wait for Wi-Fi, how much disk to
 * spend, and whether a finished publication keeps its download. All three change what the
 * queue does rather than how it looks, which is why they sit above the list of files rather
 * than inside it.
 */
@Composable
private fun Policy(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    highlight: SettingsAnchor?,
) {
    val palette = LocalStoryArcPalette.current
    val context = androidx.compose.ui.platform.LocalContext.current

    SwitchRow(
        title = stringResource(R.string.downloads_wifi_only),
        note = stringResource(R.string.downloads_wifi_only_note),
        checked = settings.downloadOverWifiOnly,
        modifier = Modifier.settingsHighlight(SettingsAnchor.DOWNLOADS_WIFI_ONLY, highlight),
    ) { onChange(settings.copy(downloadOverWifiOnly = it)) }

    SwitchRow(
        title = stringResource(R.string.downloads_remove_after),
        note = stringResource(R.string.downloads_remove_after_note),
        checked = settings.removeDownloadsAfterFinishing,
        modifier = Modifier.settingsHighlight(
            SettingsAnchor.DOWNLOADS_REMOVE_AFTER_FINISHING,
            highlight,
        ),
    ) { onChange(settings.copy(removeDownloadsAfterFinishing = it)) }

    // A short ladder rather than a free number: a reader knows "about two gigabytes", not
    // 2_147_483_648, and a text field for a byte count is a way to mistype one.
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier
            .padding(top = StoryArcSpace.sm)
            .settingsHighlight(SettingsAnchor.DOWNLOADS_LIMIT, highlight),
    ) {
        Text(
            text = stringResource(R.string.downloads_limit),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
            LIMITS.forEach { limit ->
                FilterChip(
                    selected = settings.maximumDownloadBytes == limit,
                    onClick = { onChange(settings.copy(maximumDownloadBytes = limit)) },
                    label = {
                        Text(
                            text = limit?.let {
                                android.text.format.Formatter.formatShortFileSize(context, it)
                            } ?: stringResource(R.string.downloads_limit_none),
                        )
                    },
                )
            }
        }
    }
}

@Composable
private fun SwitchRow(
    title: String,
    note: String,
    checked: Boolean,
    modifier: Modifier = Modifier,
    onChange: (Boolean) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = palette.textPrimary)
            Text(note, style = MaterialTheme.typography.labelLarge, color = palette.textTertiary)
        }
        Switch(checked = checked, onCheckedChange = null)
    }
}

/**
 * Null is "no limit", and it comes first because it is the default.
 *
 * Round decimal values rather than powers of two: the platform formats a size in decimal
 * gigabytes, so 2^30 renders as "1.1 GB" and a ladder of those reads like a mistake.
 */
private val LIMITS = listOf<Long?>(null, 1_000_000_000, 5_000_000_000, 20_000_000_000)
