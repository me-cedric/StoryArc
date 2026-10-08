package app.storyarc.feature.settings

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.LibrarySyncRunner
import app.storyarc.core.persistence.SyncPlaceChoice
import app.storyarc.core.persistence.SyncStatus
import kotlinx.coroutines.launch

/**
 * Where the sync document lives, and what the sync is doing.
 *
 * `library-sync` tasks 2.1, 2.4 and 4.4. Sync is off until the reader chooses a place: a share
 * they already added, or a folder through the system picker. The rows state that every device
 * must reach the same place, and what this platform does and when. The status line is grey
 * text, never red: an unreachable place is a normal state. iOS's `SyncSettingsSection` is the
 * same section.
 */
@Composable
internal fun SyncRows(
    runner: LibrarySyncRunner,
    sources: List<Source>,
    highlight: SettingsAnchor?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val palette = LocalStoryArcPalette.current
    val status by runner.status.collectAsState()
    val choice = runner.choice.takeIf { status != SyncStatus.Off }
    var refusal by remember { mutableStateOf<Int?>(null) }
    var isListingShares by remember { mutableStateOf(false) }
    val shares = sources.filter { it.kind == SourceKind.NETWORK_SHARE }

    fun choose(next: SyncPlaceChoice?) {
        SyncFolderGrant.releaseIfLeaving(context.contentResolver, runner.choice, next)
        runner.choose(next)
        if (next != null) scope.launch { runner.run(LibrarySyncRunner.Trigger.CHOSEN) }
    }

    val pickFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
        if (tree == null) return@rememberLauncherForActivityResult
        val refused = SyncFolderGrant.take(context.contentResolver, tree)
        if (refused == null) choose(SyncPlaceChoice.Folder(tree.toString())) else refusal = refused
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
        Text(
            text = stringResource(R.string.sync_title),
            style = MaterialTheme.typography.titleSmall,
            color = palette.textPrimary,
        )
        if (choice == null) {
            Text(stringResource(R.string.sync_about), style = MaterialTheme.typography.bodySmall, color = palette.textSecondary)
            if (shares.isNotEmpty()) {
                Box {
                    SyncRow(Icons.Filled.Dns, stringResource(R.string.sync_choose_share), null, highlight) {
                        isListingShares = true
                    }
                    DropdownMenu(expanded = isListingShares, onDismissRequest = { isListingShares = false }) {
                        shares.forEach { share ->
                            DropdownMenuItem(
                                text = { Text(share.displayName) },
                                onClick = {
                                    isListingShares = false
                                    choose(SyncPlaceChoice.Share(share.id))
                                },
                            )
                        }
                    }
                }
            }
            SyncRow(Icons.Filled.Folder, stringResource(R.string.sync_choose_folder), SettingsAnchor.SYNC, highlight) {
                pickFolder.launch(null)
            }
        } else {
            val place = placeName(choice, sources, context.contentResolver)
            Row(
                modifier = Modifier.fillMaxWidth().settingsHighlight(SettingsAnchor.SYNC, highlight),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(stringResource(R.string.sync_place), style = MaterialTheme.typography.bodyMedium, color = palette.textPrimary)
                Text(place, style = MaterialTheme.typography.bodyMedium, color = palette.textSecondary)
            }
            val shown = status
            syncStatusLine(shown)?.let { (line, needsPlace) ->
                val text = when {
                    shown is SyncStatus.Synced -> stringResource(line, syncedAt(context, shown.atEpochMillis))
                    needsPlace -> stringResource(line, place)
                    else -> stringResource(line)
                }
                Text(text, style = MaterialTheme.typography.bodySmall, color = palette.textSecondary)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                TextButton(
                    onClick = { scope.launch { runner.run(LibrarySyncRunner.Trigger.CHOSEN) } },
                    enabled = status != SyncStatus.Syncing,
                ) { Text(stringResource(R.string.sync_now)) }
                TextButton(onClick = { choose(null) }) { Text(stringResource(R.string.sync_turn_off)) }
            }
        }
        Text(stringResource(R.string.sync_every_device), style = MaterialTheme.typography.bodySmall, color = palette.textSecondary)
        Text(stringResource(R.string.sync_when), style = MaterialTheme.typography.bodySmall, color = palette.textSecondary)
    }

    refusal?.let { sentence ->
        AlertDialog(
            onDismissRequest = { refusal = null },
            text = { Text(stringResource(sentence)) },
            confirmButton = { TextButton(onClick = { refusal = null }) { Text(stringResource(android.R.string.ok)) } },
        )
    }
}

@Composable
private fun SyncRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    anchor: SettingsAnchor?,
    highlight: SettingsAnchor?,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .let { if (anchor != null) it.settingsHighlight(anchor, highlight) else it }
            .clickableRow(onClick),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = LocalStoryArcPalette.current.accent)
        Text(label, style = MaterialTheme.typography.bodyMedium, color = LocalStoryArcPalette.current.textPrimary)
    }
}

/**
 * The status line's sentence, and whether it names the place. Null when there is nothing to say.
 * Lifted out of the rows so a test reads which sentence each state draws.
 */
internal fun syncStatusLine(status: SyncStatus): Pair<Int, Boolean>? = when (status) {
    SyncStatus.Off -> null
    SyncStatus.Idle -> R.string.sync_status_idle to false
    SyncStatus.Syncing -> R.string.sync_status_syncing to false
    is SyncStatus.Synced -> R.string.sync_status_synced to false
    SyncStatus.Unreachable -> R.string.sync_status_unreachable to true
    is SyncStatus.Refused -> when (status.reason) {
        is LibraryDocumentFailure.NewerThanThisApp -> R.string.sync_status_newer to false
        else -> R.string.sync_status_not_library to false
    }
}

/** The time of today's sync, or the date and time of an older one. */
private fun syncedAt(context: android.content.Context, atEpochMillis: Long): String {
    val today = DateUtils.isToday(atEpochMillis)
    val flags = DateUtils.FORMAT_SHOW_TIME or if (today) 0 else DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH
    return DateUtils.formatDateTime(context, atEpochMillis, flags)
}

/** What the chosen place is called: the share's name, or the folder's. */
private fun placeName(choice: SyncPlaceChoice, sources: List<Source>, resolver: ContentResolver): String = when (choice) {
    is SyncPlaceChoice.Share -> sources.firstOrNull { it.id == choice.sourceId }?.displayName.orEmpty()
    is SyncPlaceChoice.Folder -> SyncFolderGrant.name(resolver, Uri.parse(choice.tree))
}

/**
 * The sync folder's grant: read and write, persisted, and given back when the reader leaves it.
 *
 * `library-sync` task 2.3 reuses the grant `local-library` takes for a picked folder, with write
 * added. A library folder holds a read grant on its tree, and the library reads every read-only
 * tree grant as one of its folders, so a folder that already is a library is refused here rather
 * than taken from the library.
 */
internal object SyncFolderGrant {
    private const val READ_WRITE = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

    /** Takes the grant. @return null when it is held, or the sentence that says why not. */
    fun take(resolver: ContentResolver, tree: Uri): Int? {
        if (resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && !it.isWritePermission }) {
            return R.string.sync_folder_is_library
        }
        return try {
            resolver.takePersistableUriPermission(tree, READ_WRITE)
            null
        } catch (_: SecurityException) {
            R.string.sync_folder_refused
        }
    }

    /** Gives back the old folder's grant when the reader chooses another place or turns sync off. */
    fun releaseIfLeaving(resolver: ContentResolver, current: SyncPlaceChoice?, next: SyncPlaceChoice?) {
        if (current !is SyncPlaceChoice.Folder || current == next) return
        runCatching { resolver.releasePersistableUriPermission(Uri.parse(current.tree), READ_WRITE) }
    }

    /** The folder's name as its provider states it, or the last part of its path. */
    fun name(resolver: ContentResolver, tree: Uri): String {
        val document = runCatching {
            android.provider.DocumentsContract.buildDocumentUriUsingTree(
                tree,
                android.provider.DocumentsContract.getTreeDocumentId(tree),
            )
        }.getOrNull()
        val named = document?.let { uri ->
            runCatching {
                resolver.query(uri, arrayOf(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null)
                    ?.use { if (it.moveToFirst()) it.getString(0) else null }
            }.getOrNull()
        }
        return named ?: tree.lastPathSegment.orEmpty().substringAfterLast(':').substringAfterLast('/')
    }
}
