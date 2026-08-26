package app.storyarc.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.StorageUsage
import kotlinx.coroutines.launch

/**
 * The privacy posture, stated rather than toggled, and the two things a reader can clear.
 *
 * `settings-and-about` asks for the posture to be "verifiable rather than merely stated",
 * and the reason there is nothing to *switch* here is the point: the app has no account, no
 * backend and no analytics, so there is nothing to opt out of. A screen full of disabled
 * toggles would imply the opposite.
 *
 * What it does have is data to give back, "individually clearable, each stating what it
 * removes and how much space it frees". The size is the point — "clear cache" with no number
 * behind it asks a reader to guess whether it is worth doing.
 *
 * Downloads are named as absent rather than shown as zero, which would imply a thing that
 * happens to be empty.
 */
@Composable
internal fun PrivacyGroup(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val usage = remember { StorageUsage(context) }

    // Measured once on entry and again after a clear, rather than on every frame: walking a
    // directory tree is not a thing to do while a list scrolls.
    var cacheBytes by remember { mutableLongStateOf(usage.cacheBytes()) }
    var historyBytes by remember { mutableLongStateOf(usage.historyBytes()) }
    var confirmingHistory by remember { mutableStateOf(false) }

    if (confirmingHistory) {
        AlertDialog(
            onDismissRequest = { confirmingHistory = false },
            title = { Text(stringResource(R.string.privacy_clear_history)) },
            text = { Text(stringResource(R.string.privacy_clear_history_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingHistory = false
                    scope.launch {
                        ProgressStore.open(context).clear()
                        historyBytes = usage.historyBytes()
                    }
                }) {
                    Text(
                        text = stringResource(R.string.privacy_clear),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingHistory = false }) {
                    Text(stringResource(R.string.settings_cancel))
                }
            },
        )
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        Text(
            text = stringResource(R.string.privacy_statement),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.privacy_sources),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )

        ClearableRow(
            titleRes = R.string.privacy_cache,
            noteRes = R.string.privacy_cache_note,
            clearLabelRes = R.string.privacy_clear_cache,
            bytes = cacheBytes,
            // No confirmation: a cache is by definition rebuildable, and asking twice for
            // something with no consequence teaches a reader to click through dialogues.
            onClear = {
                usage.clearCache()
                cacheBytes = usage.cacheBytes()
            },
        )

        ClearableRow(
            titleRes = R.string.privacy_history,
            noteRes = R.string.privacy_history_note,
            clearLabelRes = R.string.privacy_clear_history,
            bytes = historyBytes,
            onClear = { confirmingHistory = true },
        )

        Text(
            text = stringResource(R.string.privacy_downloads_absent),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )
        DiagnosticRow()
    }
}

/**
 * The diagnostic export, shown before it can be shared.
 *
 * Inline rather than on its own screen. `settings-and-about` requires the reader to see
 * the text before sharing it, and a screen they have to navigate to and back from puts
 * distance between reading it and deciding — which is the one moment that matters here.
 */
@Composable
private fun DiagnosticRow() {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    var text by remember { mutableStateOf<String?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.privacy_diagnostic),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(R.string.privacy_diagnostic_note),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
            OutlinedButton(
                // Built on show rather than on composition. It reads five stores, and a
                // Privacy screen should not do that to draw a row nobody expanded.
                onClick = { text = if (text == null) Diagnostic.text(context) else null },
            ) {
                Text(
                    stringResource(
                        if (text == null) R.string.privacy_diagnostic_show else R.string.privacy_diagnostic_hide,
                    ),
                )
            }
        }

        text?.let { report ->
            Text(
                text = report,
                style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace,
                color = palette.textSecondary,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(palette.surfaceSunken, RoundedCornerShape(StoryArcSpace.sm))
                    .padding(StoryArcSpace.sm),
            )
            // Share only. The system sheet already offers "Copy", and a second button
            // beside it would be StoryArc reimplementing a platform affordance.
            OutlinedButton(onClick = { context.startActivity(Diagnostic.shareIntent(report)) }) {
                Text(stringResource(R.string.privacy_diagnostic_share))
            }
        }
    }
}

@Composable
private fun ClearableRow(
    titleRes: Int,
    noteRes: Int,
    /** What a screen reader calls the button. Two visible "Clear"s cannot be told apart by ear. */
    clearLabelRes: Int,
    bytes: Long,
    onClear: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val clearLabel = stringResource(clearLabelRes)

    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            // A clear rewrites this size in place; without a live region TalkBack says nothing
            // and the reader cannot tell that the clear worked.
            Text(
                text = stringResource(titleRes, formatBytes(bytes)),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            Text(
                text = stringResource(noteRes),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
            )
        }
        OutlinedButton(
            onClick = onClear,
            enabled = bytes > 0,
            modifier = Modifier.semantics { contentDescription = clearLabel },
        ) {
            Text(stringResource(R.string.privacy_clear))
        }
    }
}

/**
 * A size a person can read.
 *
 * Powers of 1024 with the SI names, which is what every file manager on both platforms
 * shows — matching the convention a reader already has beats being right about kibibytes.
 */
private fun formatBytes(bytes: Long): String = when {
    bytes <= 0 -> "0 kB"
    bytes < 1024 -> "1 kB"
    bytes < 1024 * 1024 -> "${bytes / 1024} kB"
    bytes < 1024 * 1024 * 1024 -> "%.1f MB".format(bytes / (1024.0 * 1024))
    else -> "%.1f GB".format(bytes / (1024.0 * 1024 * 1024))
}
