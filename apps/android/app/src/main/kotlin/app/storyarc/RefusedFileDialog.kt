package app.storyarc

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

/**
 * What to say about a file the system handed over that StoryArc will not open.
 *
 * `local-library` is specific about the wording: the app "names the format it detected and
 * states which formats it supports, rather than reporting a generic failure". A reader who
 * picked the wrong file in another app cannot tell that from a broken StoryArc unless
 * StoryArc says which it is.
 */
@Composable
internal fun RefusedFileDialog(outcome: OpenedFile.Outcome, onDismiss: () -> Unit) {
    val message = when (outcome) {
        is OpenedFile.Outcome.Unsupported ->
            stringResource(R.string.open_in_unsupported, outcome.name, outcome.detected)
        is OpenedFile.Outcome.Unreadable ->
            stringResource(R.string.open_in_unreadable, outcome.name)
        // An opened file is not a refusal, and this dialog is only ever shown for one.
        is OpenedFile.Outcome.Opened -> return
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.open_in_refused_title)) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.open_in_dismiss)) }
        },
    )
}
