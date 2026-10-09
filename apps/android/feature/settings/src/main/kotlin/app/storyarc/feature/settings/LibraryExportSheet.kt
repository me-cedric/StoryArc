package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import app.storyarc.core.designsystem.control.TextButton
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ExportPassphraseProblem

/**
 * The sheet where a library export is set up and handed to the system document picker.
 *
 * `library-portability` tasks 2.4, 2.5 and 5.3. A `ModalBottomSheet`, for the reason
 * `FreeSpaceSheet` gives: it is a short task with one way out. iOS's `LibraryExportSheet` says
 * the same, in the same order.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibraryExportSheet(
    state: LibraryExportState,
    onExport: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberBottomSheetState(
            SheetValue.Hidden,
            setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        LibraryExportContent(state = state, onExport = onExport, onCancel = onDismiss)
    }
}

/**
 * The sheet's contents, which is where every claim about it lives.
 *
 * Its own composable because `ModalBottomSheet` is a dialog window and a unit test cannot compose
 * one; `FreeSpaceContent` is the precedent.
 */
@Composable
internal fun LibraryExportContent(
    state: LibraryExportState,
    onExport: () -> Unit,
    onCancel: () -> Unit,
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
            text = stringResource(R.string.transfer_export_title),
            style = MaterialTheme.typography.titleLarge,
            color = palette.textPrimary,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            text = stringResource(R.string.transfer_export_carries),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        // Task 2.4: the reader is told what the file is not, where the export is offered.
        Text(
            text = stringResource(R.string.transfer_export_not_what),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.transfer_export_readable),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )

        // The warning is the switch's own note, so it is read before the reader turns it on.
        SettingsSwitchRow(
            title = stringResource(R.string.transfer_export_passwords),
            note = stringResource(R.string.transfer_export_passwords_warning),
            checked = state.includesPasswords,
            onChange = { state.includesPasswords = it },
        )
        if (state.includesPasswords) PassphraseFields(state)

        if (state.hasFailed) {
            Text(
                text = stringResource(R.string.transfer_export_failed),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm, Alignment.End),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = onCancel) { Text(stringResource(R.string.transfer_cancel)) }
            if (state.isWorking) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp))
            } else {
                Button(onClick = onExport, enabled = state.canExport) {
                    Text(stringResource(R.string.transfer_export_action))
                }
            }
        }
    }
}

@Composable
private fun PassphraseFields(state: LibraryExportState) {
    val palette = LocalStoryArcPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        PassphraseField(
            value = state.passphrase,
            onChange = { state.passphrase = it },
            label = stringResource(R.string.transfer_passphrase),
        )
        PassphraseField(
            value = state.confirmation,
            onChange = { state.confirmation = it },
            label = stringResource(R.string.transfer_passphrase_again),
        )
        when (state.problem) {
            ExportPassphraseProblem.EMPTY -> Problem(stringResource(R.string.transfer_export_problem_empty))
            ExportPassphraseProblem.MISMATCH -> Problem(stringResource(R.string.transfer_export_problem_mismatch))
            null -> Unit
        }
        Text(
            text = stringResource(R.string.transfer_export_passphrase_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
    }
}

@Composable
private fun Problem(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = LocalStoryArcPalette.current.textSecondary,
    )
}

/**
 * A passphrase field that is not a login: masked, no correction, and no suggestion. The reader
 * invents this phrase for one file.
 */
@Composable
internal fun PassphraseField(value: String, onChange: (String) -> Unit, label: String) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
        modifier = Modifier.fillMaxWidth(),
    )
}
