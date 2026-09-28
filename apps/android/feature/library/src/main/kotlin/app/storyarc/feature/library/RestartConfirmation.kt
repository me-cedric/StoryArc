package app.storyarc.feature.library

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.Publication

/**
 * `reading-progress` requires "Start from the beginning" to clear progress "only after
 * confirmation": one dialogue, called from every surface [AddToShelfSheet] offers the
 * action on, rather than the same six lines written out again at each one.
 *
 * Destructive: the position is the only copy the app promises never to lose.
 */
@Composable
fun RestartConfirmation(
    publication: Publication,
    viewModel: LibraryViewModel,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.library_restart_title, publication.displayTitle)) },
        text = { Text(stringResource(R.string.library_restart_body)) },
        confirmButton = {
            TextButton(onClick = {
                viewModel.restart(publication)
                onDismiss()
            }) {
                Text(
                    text = stringResource(R.string.library_restart_confirm),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shelves_cancel))
            }
        },
    )
}
