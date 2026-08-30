package app.storyarc.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.ImportedCopies
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind

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
 */
@Composable
internal fun SourcesGroup(
    sources: List<Source>,
    itemCount: (Source) -> Int,
    onRemove: (Source) -> Unit,
    onRename: (Source, String) -> Unit,
    /**
     * Opens a source's own screen.
     *
     * The row itself, not a chevron beside four other buttons: `sources` calls the detail a
     * screen a reader "opens", and a row that is already announced as one element is the
     * thing they will press.
     */
    onOpen: (Source) -> Unit = {},
    modifier: Modifier = Modifier,
    /**
     * Moves a source one place, up or down.
     *
     * `sources` describes reordering as a drag. Compose has no drag-to-reorder, and a
     * hand-rolled one is a long-press gesture, an auto-scroll and a set of semantics
     * actions that a screen reader would still need spelled out — so this mirrors the
     * download queue in the same app, which chose two buttons for the same reason. iOS gets
     * the drag free from `List.onMove`; `STATUS.md` records the difference.
     */
    onReorder: (Source, Boolean) -> Unit = { _, _ -> },
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
            // `sources` asks the app to state what removal frees before asking. For a
            // folder that is nothing, and saying so is the point: a reader must not have to
            // guess whether this deletes their comics.
            text = {
                Text(
                    pluralStringResource(
                        R.plurals.sources_remove_body,
                        itemCount(source),
                        itemCount(source),
                    ),
                )
            },
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

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        if (sources.isEmpty()) {
            // A reader with no source is not looking at a broken screen. `sources` wants the
            // app usable "in under ten seconds", and the library's empty state is where a
            // folder gets picked — so this points there rather than duplicating the picker.
            Text(
                text = stringResource(R.string.sources_none),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
            return@Column
        }

        sources.forEachIndexed { index, source ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clickable(
                        onClickLabel = stringResource(
                            R.string.sources_detail_open,
                            source.displayName,
                        ),
                    ) { onOpen(source) }
                    // One control per row, announced once rather than as three unrelated
                    // pieces of text on the way past.
                    .semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(icon(source.kind), contentDescription = null, tint = palette.accent)

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
                ) {
                    Text(
                        text = source.displayName,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                    )
                    // The state and the count, which is what `sources` asks a source's own
                    // screen to show. Downloads are absent because nothing downloads yet,
                    // and the count is what exists in their place.
                    //
                    // One line, joined by a separator, rather than the state in a column of
                    // its own. Two data fields and a separator is what `AboutGroup` does
                    // with a licence and its reason, for the same reason: a fixed-width
                    // column beside four icon buttons left the name a single character
                    // wide, which an emulator showed and a preview did not.
                    Text(
                        text = stringResource(status(source.state)) + " · " +
                            pluralStringResource(
                                R.plurals.sources_detail,
                                itemCount(source),
                                itemCount(source),
                            ),
                        style = MaterialTheme.typography.labelLarge,
                        color = palette.textTertiary,
                    )

                    // Said rather than left to be discovered. A catalogue can offer to pin a
                    // certificate the system refuses; Kavita cannot, and a reader whose
                    // self-signed NAS certificate was accepted for the OPDS endpoint on the
                    // same box would otherwise read the Kavita refusal as an unreachable
                    // server. Rank 15 of the 30 August security review.
                    if (source.kind == SourceKind.KAVITA_SERVER) {
                        Text(
                            text = stringResource(R.string.sources_kavita_system_trust),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textTertiary,
                        )
                    }
                }

                // Only where there is an order to change. One source cannot be reordered,
                // and the ends of the list cannot go further — a disabled arrow on every
                // first and last row is two permanently dead controls.
                if (sources.size > 1) {
                    // The tint follows `enabled`. An explicit tint overrides the one
                    // `IconButton` would have dimmed, so the first row's up arrow and the
                    // last row's down arrow looked live while doing nothing.
                    val canMoveEarlier = index > 0
                    val canMoveLater = index < sources.lastIndex
                    IconButton(onClick = { onReorder(source, false) }, enabled = canMoveEarlier) {
                        Icon(
                            imageVector = Icons.Filled.KeyboardArrowUp,
                            contentDescription = stringResource(
                                R.string.sources_move_earlier,
                                source.displayName,
                            ),
                            tint = if (canMoveEarlier) palette.textSecondary else palette.textTertiary,
                        )
                    }
                    IconButton(onClick = { onReorder(source, true) }, enabled = canMoveLater) {
                        Icon(
                            imageVector = Icons.Filled.KeyboardArrowDown,
                            contentDescription = stringResource(
                                R.string.sources_move_later,
                                source.displayName,
                            ),
                            tint = if (canMoveLater) palette.textSecondary else palette.textTertiary,
                        )
                    }
                }

                IconButton(onClick = {
                    // Seeded with the current name rather than blank: a rename is usually a
                    // correction, and retyping a folder's whole name to fix one letter is
                    // not a correction.
                    draftName = source.displayName
                    renaming = source
                }) {
                    Icon(
                        imageVector = Icons.Filled.Edit,
                        contentDescription = stringResource(
                            R.string.sources_rename_action,
                            source.displayName,
                        ),
                        tint = palette.textSecondary,
                    )
                }

                // "On this device" is not a source the reader added, so it is not one they
                // can remove. `local-library` deletes an imported copy one at a time, naming
                // the title and the space each frees; a remove here would delete every copy
                // at once behind a sentence that could name none of them.
                if (source.id != ImportedCopies.SOURCE_ID) {
                    IconButton(onClick = { removing = source }) {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = stringResource(
                                R.string.sources_remove_action,
                                source.displayName,
                            ),
                            tint = palette.textSecondary,
                        )
                    }
                }
            }
        }
    }
}

private fun icon(kind: SourceKind): ImageVector = when (kind) {
    SourceKind.LOCAL_FOLDER -> Icons.Filled.Folder
    SourceKind.NETWORK_SHARE -> Icons.Filled.Storage
    SourceKind.OPDS_CATALOG -> Icons.Filled.RssFeed
    SourceKind.KAVITA_SERVER -> Icons.Filled.Dns
}

private fun status(state: SourceConnectionState): Int = when (state) {
    is SourceConnectionState.Connected -> R.string.sources_state_connected
    is SourceConnectionState.Connecting -> R.string.sources_state_connecting
    is SourceConnectionState.Unreachable -> R.string.sources_state_unreachable
    is SourceConnectionState.Unauthorized -> R.string.sources_state_unauthorized
}
