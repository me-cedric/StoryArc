package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import app.storyarc.core.designsystem.control.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.ImportedCopies
import app.storyarc.core.persistence.LibraryImportOutcome
import app.storyarc.core.persistence.LibrarySyncRunner
import app.storyarc.core.persistence.LibraryTransfer
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRemovalWording
import app.storyarc.core.model.reachesOnlyAnotherDevice

/**
 * Every configured source, and what can be done to one.
 *
 * `sources` requires the registry to be reachable, and until now it was not: the library's
 * own source list only appears in a corner of its empty state, and this group said "not
 * built yet". The registry existed and nothing showed it.
 *
 * Handed its data rather than owning it. A feature module never depends on another feature
 * module (docs/architecture), and the registry belongs to the library — so the app layer
 * passes it through and takes the removal back.
 *
 * The icon and the state wording are mapped here rather than shared with the library's
 * own mapping, for the reason that file gives: the domain enums live in `:core:model` and
 * carry no resources, so each feature names them in its own strings.
 *
 * `onAddFolder`/`onImport`/`onAddCatalogue`/`onAddKavita`/`onAddShare`: task 17.9 moves the
 * add-a-source control here from the library toolbar, task 1.2's own direction for where it
 * belongs. The five actions are the library's `AddSourceMenu` ones, under this feature's own
 * button and its own strings, for the same reason the icon and the state wording above are.
 */
@Composable
internal fun SourcesGroup(
    sources: List<Source>,
    itemCount: (Source) -> Int,
    /** Whether that count is a slice of what the source holds. `SourceSlice` says why. */
    isPartial: (Source) -> Boolean = { false },
    /**
     * Everything the detail screen says about one source, asked of the same function that
     * screen is given, so the removal confirmation raised here and the one raised there cannot
     * name different figures for one source. `sources` asks the app to state how many files and
     * how much space a removal frees; the count of titles alone cannot say either.
     */
    diagnose: (Source) -> SourceDiagnosis,
    onRemove: (Source) -> Unit,
    onRename: (Source, String) -> Unit,
    /**
     * Opens a source's own screen.
     *
     * The row itself, not a chevron beside an overflow button: `sources` calls the detail a
     * screen a reader "opens", and a row that is already announced as one element is the
     * thing they will press.
     */
    onOpen: (Source) -> Unit = {},
    onAddFolder: () -> Unit = {},
    onImport: () -> Unit = {},
    onAddCatalogue: () -> Unit = {},
    onAddKavita: () -> Unit = {},
    onAddShare: () -> Unit = {},
    modifier: Modifier = Modifier,
    /**
     * Moves a source one place: `true` later, `false` earlier.
     *
     * Called by the row's overflow menu, by its TalkBack actions, and once for each row height
     * a drag on its handle travels (`SourceRow`). `close-the-audited-gaps` 27.3, decision O29.
     */
    onReorder: (Source, Boolean) -> Unit = { _, _ -> },
    /**
     * Moves the whole library to or from a file. Null hides the two rows, which a screen with no
     * stores behind it (a preview, a test) has no use for. `library-portability`.
     */
    transfer: LibraryTransfer? = null,
    onLibraryImported: (LibraryImportOutcome) -> Unit = {},
    /** Where the sync document lives. Null hides the rows, as [transfer] does. `library-sync`. */
    syncRunner: LibrarySyncRunner? = null,
    highlight: SettingsAnchor? = null,
) {
    val palette = LocalStoryArcPalette.current
    var removing by remember { mutableStateOf<Source?>(null) }
    var renaming by remember { mutableStateOf<Source?>(null) }
    var draftName by remember { mutableStateOf("") }

    // `sources` requires a rename to appear "everywhere the source is referenced", which it
    // does because the registry keeps the identifier and only the name moves.
    renaming?.let { source ->
        AlertDialog(
            onDismissRequest = { renaming = null },
            title = { Text(stringResource(R.string.sources_rename_title)) },
            text = {
                OutlinedTextField(
                    value = draftName,
                    onValueChange = { draftName = it },
                    singleLine = true,
                    label = { Text(stringResource(R.string.sources_rename_field)) },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    onRename(source, draftName)
                    renaming = null
                }) {
                    Text(stringResource(R.string.sources_rename_save))
                }
            },
            dismissButton = {
                TextButton(onClick = { renaming = null }) {
                    Text(stringResource(R.string.settings_cancel))
                }
            },
        )
    }

    removing?.let { source ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.sources_remove_title, source.displayName)) },
            // `sources` asks the app to state what removal frees before asking: how many files
            // and how much space. [SourceRemovalWording] picks the sentence from the same
            // diagnosis the detail screen shows, so a source with downloads is told they go
            // rather than promised that no files are deleted — which is what this body said
            // until 2026-09-05, while `SettingsHost` deleted them.
            text = { Text(removalBody(SourceRemovalWording.of(diagnose(source)))) },
            confirmButton = {
                TextButton(onClick = {
                    onRemove(source)
                    removing = null
                }) {
                    Text(
                        text = stringResource(R.string.sources_remove),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { removing = null }) {
                    Text(stringResource(R.string.settings_cancel))
                }
            },
        )
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(SOURCE_ROW_GAP)) {
        // Task 17.9: this is now the way in, moved here from the library toolbar per task
        // 1.2's own direction for where it belongs. The empty library keeps its own "Add a
        // library" call to action besides this one -- a reader who has never opened Settings
        // still has a way in.
        AddSourceButton(
            onAddFolder = onAddFolder,
            onImport = onImport,
            onAddCatalogue = onAddCatalogue,
            onAddKavita = onAddKavita,
            onAddShare = onAddShare,
        )

        if (transfer != null) {
            LibraryTransferRows(transfer = transfer, highlight = highlight, onImported = onLibraryImported)
        }

        if (syncRunner != null) SyncRows(runner = syncRunner, sources = sources, highlight = highlight)

        if (sources.isEmpty()) {
            Text(
                text = stringResource(R.string.sources_none),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
            return@Column
        }

        sources.forEachIndexed { index, source ->
            key(source.id) {
                SourceRow(
                    source = source,
                    index = index,
                    count = sources.size,
                    itemCount = itemCount(source),
                    isPartial = isPartial(source),
                    onOpen = { onOpen(source) },
                    onRename = {
                        // Seeded with the current name rather than blank: a rename is usually a
                        // correction, and retyping a folder's whole name to fix one letter is
                        // not a correction.
                        draftName = source.displayName
                        renaming = source
                    },
                    onRemove = { removing = source },
                    onReorder = { later -> onReorder(source, later) },
                )
            }
        }

        // The delete button raises the same confirmation the detail screen does, and the two
        // standing facts about removal — the downloads go, the reading positions stay thirty
        // days — have to be readable *before* it, on this surface, at every text size. Not a
        // sentence in the dialog: iOS's confirmation at the largest text size holds about
        // seven short lines and does not scroll, which is what moved the thirty days under the
        // detail screen's actions on 2026-09-05; this surface mirrors the placement so both
        // platforms say the same thing at the same moment. Only where a row can be removed,
        // which "On this device" cannot.
        if (sources.any { it.id != ImportedCopies.SOURCE_ID }) {
            Text(
                text = stringResource(R.string.sources_remove_footer),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
}

internal fun icon(kind: SourceKind): ImageVector = when (kind) {
    SourceKind.LOCAL_FOLDER -> Icons.Filled.Folder
    SourceKind.NETWORK_SHARE -> Icons.Filled.Storage
    SourceKind.OPDS_CATALOG -> Icons.Filled.RssFeed
    SourceKind.KAVITA_SERVER -> Icons.Filled.Dns
}

/**
 * The way in, task 17.9 moves here from the library toolbar.
 *
 * A text button rather than an icon: this screen names every other action it offers
 * (`sources.remove`, `sources.rename`), and the add control is the first thing a reader who
 * has never configured a source presses.
 */
@Composable
private fun AddSourceButton(
    onAddFolder: () -> Unit,
    onImport: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }

    Box {
        TextButton(onClick = { open = true }) {
            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(StoryArcSpace.xs))
            Text(stringResource(R.string.sources_add))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            AddSourceItem(SourceKind.LOCAL_FOLDER, R.string.sources_add_folder, onAddFolder) { open = false }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.sources_add_import)) },
                leadingIcon = { Icon(Icons.Filled.FileDownload, contentDescription = null) },
                onClick = { open = false; onImport() },
            )
            AddSourceItem(SourceKind.OPDS_CATALOG, R.string.sources_add_catalogue, onAddCatalogue) { open = false }
            AddSourceItem(SourceKind.KAVITA_SERVER, R.string.sources_add_kavita, onAddKavita) { open = false }
            AddSourceItem(SourceKind.NETWORK_SHARE, R.string.sources_add_share, onAddShare) { open = false }
        }
    }
}

@Composable
private fun AddSourceItem(kind: SourceKind, labelRes: Int, onClick: () -> Unit, onChosen: () -> Unit) {
    DropdownMenuItem(
        text = { Text(stringResource(labelRes)) },
        leadingIcon = { Icon(icon(kind), contentDescription = null) },
        onClick = { onChosen(); onClick() },
    )
}

internal fun status(state: SourceConnectionState): Int = when (state) {
    is SourceConnectionState.Connected -> R.string.sources_state_connected
    is SourceConnectionState.Connecting -> R.string.sources_state_connecting
    is SourceConnectionState.Unreachable -> R.string.sources_state_unreachable
    is SourceConnectionState.Unauthorized -> R.string.sources_state_unauthorized
}

/**
 * `library-sync` task 5.8: the mark of a source a sync brought from another device, or null. A
 * source whose address names that device also says that this device does not try it.
 */
internal fun otherDeviceMark(source: Source): Int? = when {
    source.reachesOnlyAnotherDevice -> R.string.sources_other_device_loopback
    source.fromAnotherDevice -> R.string.sources_other_device
    else -> null
}
