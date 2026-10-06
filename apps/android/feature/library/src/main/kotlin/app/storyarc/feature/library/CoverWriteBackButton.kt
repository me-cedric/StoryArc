package app.storyarc.feature.library

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.kavita.KavitaError
import app.storyarc.core.model.CoverWriteBack
import app.storyarc.core.model.CoverWriteOffer
import app.storyarc.core.model.CoverWriteSubject
import kotlinx.coroutines.launch

/**
 * Offers to write a chosen cover back to its source, where the source takes one.
 *
 * The offer is [CoverWriteBack.offer]'s answer and nothing else, which is what task 5.2 of
 * `cover-for-every-publication` guards: no screen grows its own copy of the condition and
 * starts offering a button that answers 403.
 *
 * **The confirmation is not a formality.** A reading-list cover is the whole server's view
 * of that list, so the dialogue says in those words that this changes the cover for everyone
 * who can see it. iOS's `CoverWriteBackButton` says the same sentence.
 */
@Composable
internal fun CoverWriteBackButton(
    subject: CoverWriteSubject,
    /**
     * The chosen cover's bytes.
     *
     * **This is the seam onto the cover-override store.** Sections 1 and 2 of this change
     * own that store and the one point that resolves a cover; this button is given the bytes
     * rather than reaching for them, so the two halves join at one function. Null means no
     * cover has been chosen, and nothing is sent: there is nothing to send.
     */
    image: suspend () -> ByteArray?,
    /**
     * Sends the cover. Supplied by the screen that holds the server's client, because a
     * composable does not build one.
     */
    send: suspend (Int, ByteArray) -> Unit,
    modifier: Modifier = Modifier,
) {
    val offer = CoverWriteBack.offer(subject)
    if (offer !is CoverWriteOffer.KavitaReadingList) return

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var confirming by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }

    TextButton(onClick = { confirming = true }, modifier = modifier) {
        Text(stringResource(R.string.covers_write_back))
    }

    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.covers_write_back)) },
            text = { Text(stringResource(R.string.covers_write_back_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    scope.launch {
                        val data = image() ?: return@launch
                        // A refusal here is loud, unlike a cover lookup's: the reader asked
                        // for this one.
                        failure = runCatching { send(offer.id, data) }.exceptionOrNull()
                            ?.let { error ->
                                describeKavita(
                                    context,
                                    error as? KavitaError ?: KavitaError.UnexpectedResponse,
                                )
                            }
                    }
                }) {
                    Text(stringResource(R.string.covers_write_back_send))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = false }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }

    failure?.let { message ->
        AlertDialog(
            onDismissRequest = { failure = null },
            title = { Text(stringResource(R.string.covers_write_back)) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { failure = null }) {
                    Text(stringResource(R.string.library_import_dismiss))
                }
            },
        )
    }
}
