package app.storyarc.feature.library

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.persistence.KavitaCardStore
import app.storyarc.core.persistence.KavitaProgressStore
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * Download and mark read, for everything a server's collection or reading list holds.
 *
 * Task 7.8 of `close-the-audited-gaps`. The same two actions the local shelves have, over a
 * server's chapters: the download states the count and the size and waits for a yes, and the
 * mark is undoable for ten seconds. iOS's `KavitaShelfBulkMenu` is its twin.
 *
 * [load] answers the chapters the shelf holds, or null when the server could not say.
 * [onMarked] is called when marks were sent or taken back, so the screen can ask the server
 * for the state it now holds.
 */
@Composable
internal fun KavitaShelfBulkMenu(
    server: KavitaPage,
    client: KavitaClient,
    queue: DownloadQueue?,
    snackbars: SnackbarHostState,
    load: suspend () -> List<KavitaShelfChapter>?,
    onMarked: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var isOpen by remember { mutableStateOf(false) }
    var isWorking by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<KavitaBulkDownloadAsk?>(null) }
    var isAllOnDevice by remember { mutableStateOf(false) }
    var undo by remember { mutableStateOf<KavitaMarkUndo?>(null) }

    val unreachable = stringResource(R.string.kavita_bulk_unreachable, server.title)
    val undoLabel = stringResource(R.string.downloads_undo)
    val changed = undo?.let {
        pluralStringResource(R.plurals.library_bulk_changed, it.chapters.size, it.chapters.size)
    }
    val store = remember(context) { KavitaProgressStore.open(context) }

    /** Marks each chapter for this server, which holds the mark if it is not there. */
    suspend fun send(chapters: List<KavitaShelfChapter>, read: Boolean) {
        KavitaShelfBulk.mark(chapters, read) { each, isRead ->
            KavitaSync.mark(store, client.address, each.origin(server.id), isRead)
        }
        onMarked()
    }

    // The ten seconds, and what happens at the end of them: nothing, or the mark taken back.
    LaunchedEffect(undo) {
        val record = undo ?: return@LaunchedEffect
        val text = changed ?: return@LaunchedEffect
        if (snackbars.offerUndo(text, undoLabel)) send(record.chapters, !record.read)
        undo = null
    }

    if (isWorking) {
        CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(24.dp))
    } else {
        IconButton(onClick = { isOpen = true }) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.shelves_bulk),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }

    DropdownMenu(expanded = isOpen, onDismissRequest = { isOpen = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_mark_read)) },
            onClick = {
                isOpen = false
                scope.launch {
                    isWorking = true
                    val held = load()
                    if (held == null) {
                        snackbars.showSnackbar(unreachable)
                    } else {
                        val moving = KavitaShelfBulk.changing(held, read = true)
                        if (moving.isNotEmpty()) {
                            send(moving, read = true)
                            undo = KavitaMarkUndo(moving, read = true)
                        }
                    }
                    isWorking = false
                }
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_bulk_download)) },
            enabled = queue != null,
            onClick = {
                isOpen = false
                scope.launch {
                    isWorking = true
                    val held = load()
                    if (held == null) {
                        snackbars.showSnackbar(unreachable)
                    } else {
                        val kept = KavitaCardStore.open(context).all(server.id).map { it.chapterId }.toSet()
                        val ask = KavitaShelfBulk.downloadAsk(held, kept)
                        if (ask == null) isAllOnDevice = true else pending = ask
                    }
                    isWorking = false
                }
            },
        )
    }

    if (isAllOnDevice) {
        AlertDialog(
            onDismissRequest = { isAllOnDevice = false },
            text = { Text(stringResource(R.string.library_bulk_download_none)) },
            confirmButton = {
                TextButton(onClick = { isAllOnDevice = false }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }

    pending?.let { ask ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = {
                Text(pluralStringResource(R.plurals.library_bulk_download_title, ask.count, ask.count))
            },
            text = { Text(sizeSentence(ask.size)) },
            confirmButton = {
                TextButton(onClick = {
                    pending = null
                    val source = runCatching { UUID.fromString(server.id) }.getOrNull()
                    // The process's scope, not the screen's: each keep indexes the file and
                    // files its card when the transfer lands, and a reader who leaves this
                    // screen has not asked for those steps to be dropped. So it holds the
                    // application, never this screen's activity.
                    val app = context.applicationContext
                    KavitaShelfBulk.jobs.launch {
                        KavitaShelfBulk.download(ask) { each ->
                            val queued = queue ?: return@download false
                            KavitaKeep.keep(
                                context = app,
                                chapter = each.chapter,
                                series = each.series,
                                metadata = null,
                                origin = each.origin(server.id),
                                sourceId = source,
                                client = client,
                                queue = queued,
                            ) != null
                        }
                    }
                }) {
                    Text(stringResource(R.string.library_bulk_download))
                }
            },
            dismissButton = {
                TextButton(onClick = { pending = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

/** The one sentence that states what a download will copy, in whichever way the server left it. */
@Composable
private fun sizeSentence(size: KavitaBulkSize): String {
    val context = LocalContext.current
    val formatted = { bytes: Long -> android.text.format.Formatter.formatFileSize(context, bytes) }
    return when (size) {
        is KavitaBulkSize.Known -> stringResource(R.string.library_bulk_download_size, formatted(size.bytes))
        is KavitaBulkSize.AtLeast -> stringResource(R.string.kavita_bulk_size_at_least, formatted(size.bytes))
        KavitaBulkSize.Unstated -> stringResource(R.string.kavita_bulk_size_unknown)
    }
}
