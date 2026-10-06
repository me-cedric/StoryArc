package app.storyarc.feature.library

import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

/**
 * Everything that is not reading.
 *
 * Its own file since `cover-for-every-publication` task 2.3, because
 * `PublicationDetailScreen.kt` was at the 800-line cap `scripts/line-cap.mjs` enforces and the
 * cover chooser had to go into that page. A menu of four items that shares no state with the
 * page around it is the obvious thing to lift out, and iOS already draws this page from
 * several files for the same reason.
 *
 * `publication-detail`: each of these is "available from this page without competing with
 * the primary action", and "an action that does not apply is absent, not shown disabled
 * without explanation". So download and remove-download are `null` rather than greyed when
 * the app has no way to perform them.
 */
@Composable
internal fun DetailOverflowMenu(
    isOpen: Boolean,
    onDismiss: () -> Unit,
    isFinished: Boolean,
    onMark: (Boolean) -> Unit,
    onAddToShelf: () -> Unit,
    onDownload: (() -> Unit)?,
    onRemoveDownload: (() -> Unit)?,
) {
    DropdownMenu(expanded = isOpen, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.detail_add_to_shelf)) },
            onClick = {
                onDismiss()
                onAddToShelf()
            },
        )
        DropdownMenuItem(
            text = {
                Text(
                    stringResource(
                        if (isFinished) R.string.library_mark_unread else R.string.library_mark_read,
                    ),
                )
            },
            onClick = {
                onDismiss()
                onMark(!isFinished)
            },
        )
        onDownload?.let { download ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.detail_action_download)) },
                onClick = {
                    onDismiss()
                    download()
                },
            )
        }
        onRemoveDownload?.let { remove ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.downloads_remove)) },
                onClick = {
                    onDismiss()
                    remove()
                },
            )
        }
    }
}
