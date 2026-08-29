package app.storyarc.feature.epubreader

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource

/**
 * Writing on a mark.
 *
 * A dialog rather than a sheet: it is one field and two buttons, and it is asked for while
 * the reader is looking at the words it is about. iOS presents the same thing as a
 * half-height sheet, which is where an iOS reader expects a small editor.
 */
@Composable
internal fun NoteDialog(
    initial: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var text by remember(initial) { mutableStateOf(initial) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.annotations_note)) },
        text = {
            OutlinedTextField(
                value = text,
                onValueChange = { text = it },
                modifier = Modifier,
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(text) }) {
                Text(stringResource(R.string.annotations_save))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.annotations_cancel))
            }
        },
    )
}
