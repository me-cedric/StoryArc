package app.storyarc.feature.library

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * D2: a read mark that a Kavita server cannot accept, until the reader dismisses the notice.
 *
 * A server older than Kavita 0.9.0 has no `mark-multiple-*` route. [KavitaSync] removes such a
 * mark from its queue, and this tells the reader why. A mark comes from many screens, so the
 * shell shows [KavitaMarkRefusedDialog] over the screen that is in front.
 */
object KavitaMarkRefusal {
    private val refused = MutableStateFlow(false)

    /** True after a server refused a mark, until the reader dismisses the notice. */
    val isRefused: StateFlow<Boolean> = refused.asStateFlow()

    fun note() {
        refused.value = true
    }

    fun dismiss() {
        refused.value = false
    }
}

/** The notice for a refused mark. The shell draws it once, over every destination. */
@Composable
fun KavitaMarkRefusedDialog() {
    val isRefused by KavitaMarkRefusal.isRefused.collectAsStateWithLifecycle()
    if (!isRefused) return
    AlertDialog(
        onDismissRequest = KavitaMarkRefusal::dismiss,
        title = { Text(stringResource(R.string.kavita_mark_refused_title)) },
        text = { Text(stringResource(R.string.kavita_mark_refused_body)) },
        confirmButton = {
            TextButton(onClick = KavitaMarkRefusal::dismiss) {
                Text(stringResource(R.string.library_import_dismiss))
            }
        },
    )
}
