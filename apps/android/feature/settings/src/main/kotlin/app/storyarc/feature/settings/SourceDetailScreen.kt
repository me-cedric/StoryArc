package app.storyarc.feature.settings

import android.content.Context
import android.text.format.DateUtils
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceAction
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceFailure

/**
 * One source, in full, and the five things that can be done to it.
 *
 * `sources`: opening a source's detail screen shows "the state, the last successful sync, the
 * last error in plain language, the item count, and the bytes downloaded", and offers
 * "actions to test the connection, refresh, clear the cache, remove downloads, and remove the
 * source". The settings list carried two of the fields and one of the actions; the audit
 * called the gap out, and this is the screen the scenario describes.
 *
 * Which actions this particular source is offered is [SourceDiagnosis]'s answer, not this
 * screen's — a decision with three inputs and no pixels belongs where a test can reach it.
 * iOS's `SourceDetail` draws the same rows in the same order.
 */
@Composable
internal fun SourceDetailScreen(
    source: Source,
    diagnosis: SourceDiagnosis,
    onAction: (SourceAction) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    var confirming by remember { mutableStateOf<SourceAction?>(null) }

    confirming?.let { action ->
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text(stringResource(confirmTitle(action), source.displayName)) },
            // Stated before it is asked, per `sources`: a reader must not have to guess
            // whether this deletes their comics.
            text = {
                if (action == SourceAction.REMOVE_DOWNLOADS) {
                    Text(
                        stringResource(
                            R.string.sources_remove_downloads_body,
                            Formatter.formatFileSize(context, diagnosis.downloadedBytes),
                        ),
                    )
                } else {
                    Text(
                        pluralStringResource(
                            R.plurals.sources_remove_body,
                            diagnosis.itemCount,
                            diagnosis.itemCount,
                        ),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = null
                    onAction(action)
                    // The screen goes with the source. A detail screen for a source that is
                    // no longer in the registry is a page describing nothing, and its
                    // remaining buttons would act on an id the app has already forgotten.
                    if (action == SourceAction.REMOVE) onBack()
                }) {
                    Text(
                        text = stringResource(label(action)),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = null }) {
                    Text(stringResource(R.string.settings_cancel))
                }
            },
        )
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(source.displayName) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.settings_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            Field(
                label = stringResource(R.string.sources_detail_status),
                value = stringResource(status(diagnosis.state)),
            )
            Field(
                label = stringResource(R.string.sources_detail_last_sync),
                value = diagnosis.lastSuccessfulSyncEpochMillis?.let { moment(context, it) }
                    ?: stringResource(R.string.sources_detail_never),
            )
            diagnosis.failure?.let { failure ->
                Field(
                    label = stringResource(R.string.sources_detail_last_error),
                    // The last error, in the reader's words rather than the network's. An
                    // unreachable source names when it stopped answering; a refused
                    // credential carries its own sentence, written where the refusal
                    // happened.
                    value = when (failure) {
                        is SourceFailure.Unreachable -> stringResource(
                            R.string.sources_detail_error_unreachable,
                            moment(context, failure.sinceEpochMillis),
                        )
                        is SourceFailure.Unauthorized -> failure.reason
                    },
                )
            }
            Field(
                label = stringResource(R.string.sources_detail_items),
                value = pluralStringResource(
                    R.plurals.sources_detail,
                    diagnosis.itemCount,
                    diagnosis.itemCount,
                ),
            )
            Field(
                label = stringResource(R.string.sources_detail_downloaded),
                value = Formatter.formatFileSize(context, diagnosis.downloadedBytes),
            )

            // `reading-progress`' *Source cannot store progress*: a source with no progress
            // mechanism keeps positions locally only, "and the source detail screen states
            // that progress for it does not sync". Under the fields rather than beside them,
            // because it is a fact about the source rather than a value that changes — and it
            // belongs on this screen rather than in the list, which describes what a kind of
            // source *is* before one exists.
            if (!source.kind.syncsReadingProgress) {
                Text(
                    text = stringResource(R.string.sources_detail_progress_local_only),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }

            diagnosis.actions.forEach { action ->
                TextButton(
                    onClick = {
                        // The two that delete bytes ask first. The other three are cheap and
                        // undoable by doing them again, and a confirmation on "Refresh" is a
                        // dialog between a reader and the thing they already asked for.
                        if (action.isDestructive) confirming = action else onAction(action)
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) {
                    Text(
                        text = stringResource(label(action)),
                        color = if (action == SourceAction.REMOVE) {
                            MaterialTheme.colorScheme.error
                        } else {
                            palette.textPrimary
                        },
                    )
                }
            }
        }
    }
}

/**
 * A label and its value, on one row.
 *
 * `settings-and-about` puts a setting's current value beside its name so it can be read
 * without entering anything, and a diagnosis is five of exactly that.
 */
@Composable
private fun Field(label: String, value: String) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            // One row, announced once rather than as two unrelated pieces of text on the
            // way past.
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
    }
}

/**
 * A moment, as the reader's own locale writes one.
 *
 * The platform's formatter rather than a pattern of this app's own: a date is one of the
 * few things every device already knows how to write, and `localization` asks for dates
 * "in the reader's locale" rather than in ours.
 */
private fun moment(context: Context, epochMillis: Long): String = DateUtils.formatDateTime(
    context,
    epochMillis,
    DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_SHOW_TIME or DateUtils.FORMAT_ABBREV_ALL,
)

private fun status(state: SourceConnectionState): Int = when (state) {
    is SourceConnectionState.Connected -> R.string.sources_state_connected
    is SourceConnectionState.Connecting -> R.string.sources_state_connecting
    is SourceConnectionState.Unreachable -> R.string.sources_state_unreachable
    is SourceConnectionState.Unauthorized -> R.string.sources_state_unauthorized
}

private fun label(action: SourceAction): Int = when (action) {
    SourceAction.RECONNECT -> R.string.sources_action_reconnect
    SourceAction.TEST_CONNECTION -> R.string.sources_action_test
    SourceAction.REFRESH -> R.string.sources_action_refresh
    SourceAction.CLEAR_CACHE -> R.string.sources_action_clear_cache
    SourceAction.REMOVE_DOWNLOADS -> R.string.sources_action_remove_downloads
    SourceAction.REMOVE -> R.string.sources_remove
}

private fun confirmTitle(action: SourceAction): Int =
    if (action == SourceAction.REMOVE_DOWNLOADS) {
        R.string.sources_remove_downloads_title
    } else {
        R.string.sources_remove_title
    }
