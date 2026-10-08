package app.storyarc.feature.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetState
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.previewLines
import app.storyarc.core.persistence.LibraryImportOutcome
import app.storyarc.core.persistence.LibraryImportPreview
import kotlin.math.roundToInt

/**
 * The sheet that states what importing a library file will do, and then does it.
 *
 * `library-portability` tasks 3.1, 5.4 and 6.8. Nothing changes until the reader taps Import. A
 * document the app refuses is refused here by name, and a wrong passphrase is stated and may be
 * tried again. iOS's `LibraryImportSheet` is the same flow.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibraryImportSheet(
    state: LibraryImportState,
    onImport: (skippingSecrets: Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = { if (!state.isBusy) onDismiss() },
        sheetState = rememberBottomSheetState(
            SheetValue.Hidden,
            setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        LibraryImportContent(state = state, onImport = onImport, onClose = onDismiss)
    }
}

/**
 * The sheet's contents, which is where every claim about it lives. Its own composable because a
 * unit test cannot compose a `ModalBottomSheet`.
 */
@Composable
internal fun LibraryImportContent(
    state: LibraryImportState,
    onImport: (skippingSecrets: Boolean) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.transfer_import_title),
            style = MaterialTheme.typography.titleLarge,
            color = palette.textPrimary,
            modifier = Modifier.semantics { heading() },
        )
        when (val phase = state.phase) {
            ImportPhase.Idle, ImportPhase.Reading, ImportPhase.Importing -> Busy()
            is ImportPhase.Preview -> PreviewBody(state, phase.preview, onImport, onClose)
            is ImportPhase.Refused -> {
                Refusal(phase.refusal)
                CloseRow(stringResource(R.string.transfer_ok), onClose)
            }
            is ImportPhase.Done -> {
                DoneBody(phase.outcome)
                CloseRow(stringResource(R.string.transfer_done_action), onClose)
            }
            ImportPhase.Failed -> {
                Text(
                    text = stringResource(R.string.transfer_import_failed),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                CloseRow(stringResource(R.string.transfer_ok), onClose)
            }
        }
    }
}

@Composable
private fun Busy() {
    CircularProgressIndicator(modifier = Modifier.padding(StoryArcSpace.md))
}

@Composable
private fun PreviewBody(
    state: LibraryImportState,
    preview: LibraryImportPreview,
    onImport: (skippingSecrets: Boolean) -> Unit,
    onClose: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(R.string.transfer_import_intro),
        style = MaterialTheme.typography.bodyMedium,
        color = palette.textPrimary,
    )
    ImportPreviewList(preview.plan.previewLines())

    if (preview.needsPassphrase) {
        Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
            Text(
                text = stringResource(R.string.transfer_import_secrets),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            PassphraseField(
                value = state.passphrase,
                onChange = { state.passphrase = it },
                label = stringResource(R.string.transfer_passphrase),
            )
            if (state.passphraseRefused) {
                Text(
                    text = stringResource(R.string.transfer_import_wrong),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }
            TextButton(onClick = { onImport(true) }) {
                Text(stringResource(R.string.transfer_import_without_secrets))
            }
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm, Alignment.End),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(onClick = onClose) { Text(stringResource(R.string.transfer_cancel)) }
        Button(
            onClick = { onImport(false) },
            enabled = !preview.needsPassphrase || state.passphrase.isNotEmpty(),
        ) {
            Text(stringResource(R.string.transfer_import_action))
        }
    }
}

/** The reason, by name: a newer version names both numbers and a too-large file both sizes. */
@Composable
internal fun Refusal(refusal: ImportRefusal) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    Text(
        text = stringResource(R.string.transfer_refused_title),
        style = MaterialTheme.typography.titleSmall,
        color = palette.textPrimary,
    )
    val reason = when (refusal) {
        is ImportRefusal.Document -> when (val failure = refusal.failure) {
            is LibraryDocumentFailure.NewerThanThisApp ->
                stringResource(R.string.transfer_refused_newer, failure.found, failure.understood)
            is LibraryDocumentFailure.TooLarge -> stringResource(
                R.string.transfer_refused_too_large,
                Formatter.formatShortFileSize(context, failure.found),
                Formatter.formatShortFileSize(context, failure.limit),
            )
            LibraryDocumentFailure.NotALibraryDocument -> stringResource(R.string.transfer_refused_not_a_document)
            is LibraryDocumentFailure.NoMigrationPath,
            is LibraryDocumentFailure.Malformed,
            -> stringResource(R.string.transfer_refused_damaged)
        }
        ImportRefusal.Unopened -> stringResource(R.string.transfer_refused_unopened)
    }
    Text(text = reason, style = MaterialTheme.typography.bodyMedium, color = palette.textSecondary)
}

@Composable
private fun DoneBody(outcome: LibraryImportOutcome) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(R.string.transfer_done_title),
        style = MaterialTheme.typography.titleSmall,
        color = palette.textPrimary,
    )
    if (outcome.secretsWritten > 0) {
        Text(
            text = pluralStringResource(
                R.plurals.transfer_done_secrets,
                outcome.secretsWritten,
                outcome.secretsWritten,
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
    }
    if (outcome.sourcesNeedingSignIn.isNotEmpty()) {
        val count = outcome.sourcesNeedingSignIn.size
        Text(
            text = pluralStringResource(R.plurals.transfer_done_sign_in, count, count),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        outcome.sourcesNeedingSignIn.forEach {
            Text(text = it, style = MaterialTheme.typography.labelLarge, color = palette.textSecondary)
        }
    }
    if (outcome.conflicts.isNotEmpty()) ConflictRows(outcome.conflicts)
}

/** D3's notice, once: one title names both positions, several give the count and a list. */
@Composable
private fun ConflictRows(conflicts: List<ProgressPull.Conflict>) {
    val palette = LocalStoryArcPalette.current
    var listed by remember { mutableStateOf(false) }
    val only = conflicts.singleOrNull()
    if (only != null) {
        Text(
            text = stringResource(
                R.string.transfer_done_conflict_one,
                positionWords(only.resolved.position),
                positionWords(only.discarded),
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        return
    }
    Text(
        text = pluralStringResource(R.plurals.transfer_done_conflict_many, conflicts.size, conflicts.size),
        style = MaterialTheme.typography.bodyMedium,
        color = palette.textPrimary,
    )
    TextButton(onClick = { listed = !listed }) { Text(stringResource(R.string.transfer_done_conflict_show)) }
    if (listed) conflicts.forEach { ConflictRow(it) }
}

/** One title both devices had moved on in: the position kept and the position set aside. */
@Composable
internal fun ConflictRow(conflict: ProgressPull.Conflict) {
    Text(
        text = stringResource(
            R.string.transfer_done_conflict_item,
            positionWords(conflict.resolved.position),
            positionWords(conflict.discarded),
        ),
        style = MaterialTheme.typography.labelLarge,
        color = LocalStoryArcPalette.current.textSecondary,
    )
}

/**
 * A position in the unit it already keeps: a page's own index where the count is known, a
 * percentage otherwise. The same rule as the Kavita conflict notice, worded in this module's own
 * strings.
 */
@Composable
internal fun positionWords(position: ReadingPosition): String =
    if (position is ReadingPosition.Page && position.total > 0) {
        stringResource(R.string.transfer_position_page, position.index + 1, position.total)
    } else {
        stringResource(R.string.transfer_position_percent, (position.fraction * 100).roundToInt())
    }

@Composable
private fun CloseRow(label: String, onClose: () -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Button(onClick = onClose) { Text(label) }
    }
}
