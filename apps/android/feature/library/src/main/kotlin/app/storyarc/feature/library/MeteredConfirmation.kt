package app.storyarc.feature.library

import android.text.format.Formatter
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry

/**
 * What the reader is being asked to spend mobile data on.
 *
 * A value rather than a flag, because the dialog names the publication and states its size,
 * and both have to survive the dialog being raised from a cell one level down from the
 * screen that presents it. iOS's `MeteredAsk` is the same record.
 */
data class MeteredAsk(
    val entry: OpdsEntry,
    val acquisition: OpdsAcquisition,
    /** What the app can honestly say the download weighs, or null when nothing can. */
    val bytes: Long?,
)

/**
 * The confirmation `offline-downloads`' *Overriding once* requires.
 *
 * > when a user explicitly downloads a specific publication while on a metered connection,
 * > the app confirms **with the size** and proceeds **for that item only**.
 *
 * One composable rather than a dialog written into each screen, for the reason iOS uses one
 * modifier: the browser offers the download from a cell and the detail screen offers it from
 * a format row, and a second copy of this wording is a second thing to get wrong.
 *
 * **The size, and the honest absence of one.** An OPDS acquisition link carries no `length`,
 * so before a first download the app usually has no figure -- and `offline-downloads` is
 * explicit elsewhere that a fabricated size is worse than an honest blank. The dialog
 * therefore has two bodies, and the one without a number says so in words rather than
 * showing a zero. Where a figure *is* known it is formatted by [Formatter.formatShortFileSize],
 * the same call the Downloads destination and the storage rows already use.
 */
@Composable
internal fun MeteredConfirmation(
    ask: MeteredAsk?,
    onDismiss: () -> Unit,
    onConfirm: (MeteredAsk) -> Unit,
) {
    if (ask == null) return
    val context = LocalContext.current

    AlertDialog(
        onDismissRequest = onDismiss,
        // The wording is already translated, four times, for the share that asks the same
        // question before streaming. One question, one sentence.
        title = { Text(stringResource(R.string.smb_metered_title)) },
        text = {
            Text(
                if (ask.bytes != null) {
                    stringResource(
                        R.string.downloads_metered_body,
                        ask.entry.title,
                        Formatter.formatShortFileSize(context, ask.bytes),
                    )
                } else {
                    stringResource(R.string.downloads_metered_body_unstated, ask.entry.title)
                },
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(ask) }) {
                Text(stringResource(R.string.catalogue_acquire_download))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.shelves_cancel))
            }
        },
    )
}
