package app.storyarc.feature.epubreader

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.ExternalLink

/**
 * Names where a link out of the book goes, before it goes there.
 *
 * The destination is the publication's choice and so is the link text, so the one thing the
 * reader cannot get off the page is the host. A confirmation is the only place it fits, and
 * the default action is the one that stays in the book.
 *
 * iOS shows the same question as a confirmation dialog in `EpubReaderView`.
 */
@Composable
internal fun LeaveTheBookDialog(
    leaving: ExternalLink,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.epub_leave_ask, leaving.host)) },
        confirmButton = {
            TextButton(onClick = onOpen) {
                Text(stringResource(R.string.epub_leave_open))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.epub_leave_cancel))
            }
        },
    )
}
