package app.storyarc.feature.library

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.ReadingPosition
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The reader-facing notice for `reading-progress`'s conflicts, once for the whole refresh
 * rather than once per chapter.
 *
 * D3: one conflict names both positions in the notice itself. Several give the count and a
 * "Show" action that opens a list naming both positions for every title.
 */
@Composable
fun SyncConflictNotice(conflicts: List<KavitaConflict>, onKeep: () -> Unit, onTake: (List<KavitaConflict>) -> Unit) {
    if (conflicts.isEmpty()) return
    var showingList by remember(conflicts) { mutableStateOf(false) }

    if (showingList) {
        AlertDialog(
            onDismissRequest = { showingList = false },
            title = { Text(stringResource(R.string.sync_conflict_title)) },
            text = {
                LazyColumn {
                    items(conflicts) { conflict -> Text(item(conflict)) }
                }
            },
            confirmButton = {
                TextButton(onClick = { showingList = false; onKeep() }) {
                    Text(stringResource(R.string.sync_conflict_keep))
                }
            },
            dismissButton = {
                TextButton(onClick = { showingList = false; onTake(conflicts) }) {
                    Text(stringResource(R.string.sync_conflict_take))
                }
            },
        )
        return
    }

    AlertDialog(
        onDismissRequest = onKeep,
        title = { Text(stringResource(R.string.sync_conflict_title)) },
        text = { Text(if (conflicts.size == 1) bodyOne(conflicts.first()) else count(conflicts.size)) },
        confirmButton = {
            TextButton(onClick = onKeep) {
                Text(stringResource(R.string.sync_conflict_keep))
            }
        },
        dismissButton = {
            Row {
                if (conflicts.size > 1) {
                    TextButton(onClick = { showingList = true }) {
                        Text(stringResource(R.string.sync_conflict_show))
                    }
                }
                TextButton(onClick = { onTake(conflicts) }) {
                    Text(stringResource(R.string.sync_conflict_take))
                }
            }
        },
    )
}

@Composable
private fun count(count: Int) = stringResource(R.string.sync_conflict_body, count)

@Composable
private fun bodyOne(conflict: KavitaConflict) = stringResource(
    R.string.sync_conflict_body_one,
    conflict.title,
    label(conflict.resolved.position),
    label(conflict.discarded),
)

@Composable
private fun item(conflict: KavitaConflict) = stringResource(
    R.string.sync_conflict_item,
    conflict.title,
    label(conflict.resolved.position),
    label(conflict.discarded),
)

@Composable
private fun label(position: ReadingPosition): String = formatPosition(
    position,
    stringResource(R.string.sync_position_page),
    stringResource(R.string.sync_position_percent),
)

/**
 * A position, in the unit it already keeps: a page's own index, or a percentage where there
 * is no page count. Pure, and the format strings passed in rather than read here, so it is
 * testable with no Android resources loaded.
 */
internal fun formatPosition(position: ReadingPosition, pageFormat: String, percentFormat: String): String {
    val page = position as? ReadingPosition.Page
    if (page != null && page.total > 0) {
        return String.format(Locale.getDefault(), pageFormat, page.index + 1, page.total)
    }
    return String.format(Locale.getDefault(), percentFormat, (position.fraction * 100).roundToInt())
}
