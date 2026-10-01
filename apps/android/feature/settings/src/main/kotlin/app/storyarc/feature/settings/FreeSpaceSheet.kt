package app.storyarc.feature.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.largestFirst
import app.storyarc.core.persistence.RemovedDownload
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The remedy the storage hold names but used not to offer: finished publications, largest
 * first, each removable without leaving Settings.
 *
 * `offline-downloads`' *Storage limit* says the app "pauses downloads" and the hold "states
 * a remedy"; until now that remedy was a sentence pointing at a screen with no action of its
 * own. This sheet is that action, with the same ten-second undo every other removal offers.
 * iOS's `FreeSpaceSheet.swift` is the same sheet.
 *
 * **A `ModalBottomSheet`, not a dialog**, for the reason `WhatsNewSheet` already gives: this
 * is a short list of items, not a multi-step task, which is exactly what Material's own
 * guidance names a modal sheet for.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FreeSpaceSheet(
    downloads: DownloadLibrary,
    onRemove: suspend (Download) -> RemovedDownload?,
    onRestore: suspend (RemovedDownload) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberBottomSheetState(
            SheetValue.Hidden,
            setOf(SheetValue.Hidden, SheetValue.Expanded),
        ),
    ) {
        FreeSpaceContent(downloads = downloads, onRemove = onRemove, onRestore = onRestore)
    }
}

/**
 * The sheet's contents, which is where every claim about it actually lives.
 *
 * Its own composable because `ModalBottomSheet` is a dialog window and a unit test cannot
 * compose one -- `WhatsNewSheet`'s own `WhatsNewContent` is the precedent. `FreeSpaceSheetTest`
 * composes this directly.
 */
@Composable
internal fun FreeSpaceContent(
    downloads: DownloadLibrary,
    onRemove: suspend (Download) -> RemovedDownload?,
    onRestore: suspend (RemovedDownload) -> Unit,
    modifier: Modifier = Modifier,
) {
    var library by remember(downloads) { mutableStateOf(downloads) }
    var removed by remember { mutableStateOf<RemovedDownload?>(null) }
    val scope = rememberCoroutineScope()
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current

    fun size(bytes: Long) = Formatter.formatShortFileSize(context, bytes)

    fun remove(download: Download) {
        scope.launch {
            val taken = onRemove(download) ?: return@launch
            library = library.removing(download.id)
            removed?.settle()
            removed = taken
        }
    }

    fun restore(taken: RemovedDownload) {
        scope.launch {
            onRestore(taken)
            library = library.queueing(taken.download)
            removed = null
        }
    }

    // Settles itself once the window closes, exactly as `FinishedDownloadSweep`'s own
    // removal does -- nobody touched the undo, so the bytes waiting beside the file go.
    LaunchedEffect(removed) {
        val taken = removed ?: return@LaunchedEffect
        delay(UNDO_WINDOW_MILLIS)
        if (removed === taken) {
            taken.settle()
            removed = null
        }
    }

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = stringResource(R.string.downloads_held_free_space),
            style = MaterialTheme.typography.headlineMedium,
            color = palette.textPrimary,
            modifier = Modifier.padding(StoryArcSpace.gutter),
        )

        Column(
            modifier = Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            for (download in library.largestFirst) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                ) {
                    Text(
                        text = download.title,
                        style = MaterialTheme.typography.bodyLarge,
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = size(download.downloadedBytes),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textSecondary,
                    )
                    IconButton(onClick = { remove(download) }) {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = stringResource(
                                R.string.downloads_remove_action,
                                download.title,
                            ),
                            tint = palette.textSecondary,
                        )
                    }
                }
            }
        }

        removed?.let { taken ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(StoryArcSpace.gutter),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.downloads_removed, taken.download.title),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                    maxLines = 2,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { restore(taken) }) {
                    Text(stringResource(R.string.downloads_undo))
                }
            }
        }
    }
}

/** `offline-downloads`: every removal is undoable "for 10 seconds". */
private const val UNDO_WINDOW_MILLIS = 10_000L
