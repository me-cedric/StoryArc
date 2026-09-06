package app.storyarc.feature.library

import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.SourceKind

/**
 * The ways to add a source that exist, behind one button.
 *
 * Its own file since the catalogue strip it used to share one with was removed: task 2.4 of
 * `one-library-three-destinations` took the per-source chips off the shelf, and this menu
 * has nothing to do with them — it is the library toolbar's way in to the add-a-source
 * sheets, and iOS keeps its own in `AddSourceMenu.swift`.
 */
@Composable
fun AddSourceMenu(
    onAddFolder: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit = {},
    onAddShare: () -> Unit = {},
    /**
     * Copies one publication into the app's own storage.
     *
     * Beside the source kinds rather than among them: `local-library` gives imported copies
     * a requirement of their own, and "On this device" is not a place a reader configures.
     */
    onImport: () -> Unit = {},
) {
    var open by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = stringResource(R.string.library_add_source),
            tint = MaterialTheme.colorScheme.primary,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        AddSourceItems(
            onChosen = { open = false },
            onAddFolder = onAddFolder,
            onImport = onImport,
            onAddCatalogue = onAddCatalogue,
            onAddKavita = onAddKavita,
            onAddShare = onAddShare,
        )
    }
}

/**
 * The five rows themselves, so the two menus that offer them cannot disagree.
 *
 * There are two ways in — this toolbar button and the empty state's plain secondary action —
 * and they held two copies of the same list. Two lists for one job is how one of them ends up
 * a row short, which is the defect iOS's `AddSourceMenu` was written to end.
 *
 * **Each of the four kinds is named and explained.** `sources` asks for "a one-line
 * explanation of each", and the live delta puts that naming here rather than on the first
 * screen: this is the secondary action, and choosing between the four is the question it asks.
 * The eight sentences were written and translated into four languages and drawn by nobody.
 * They come from [SourceKind.titleRes] and [SourceKind.explanationRes], so a fifth kind is
 * named in both menus at once rather than in whichever one was remembered.
 */
@Composable
internal fun AddSourceItems(
    onChosen: () -> Unit,
    onAddFolder: () -> Unit,
    onImport: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
) {
    SourceKindItem(SourceKind.LOCAL_FOLDER, onChosen, onAddFolder)
    DropdownMenuItem(
        text = { Text(stringResource(R.string.library_import)) },
        leadingIcon = { Icon(Icons.Filled.FileDownload, contentDescription = null) },
        onClick = {
            onChosen()
            onImport()
        },
    )
    SourceKindItem(SourceKind.OPDS_CATALOG, onChosen, onAddCatalogue)
    SourceKindItem(SourceKind.KAVITA_SERVER, onChosen, onAddKavita)
    SourceKindItem(SourceKind.NETWORK_SHARE, onChosen, onAddShare)
}

/**
 * One kind of place: what it is called, and one line saying what it is.
 *
 * Material publishes no two-line menu row, so the two lines go in the row's own text slot —
 * the shape a `ListItem` would give, without dragging a list item into a menu. iOS draws the
 * same pair as a menu button's title and subtitle, which is that platform's own shape for it.
 */
@Composable
private fun SourceKindItem(kind: SourceKind, onChosen: () -> Unit, onClick: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    DropdownMenuItem(
        text = {
            Column {
                Text(stringResource(kind.titleRes))
                Text(
                    text = stringResource(kind.explanationRes),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        },
        leadingIcon = { Icon(kind.icon, contentDescription = null) },
        onClick = {
            onChosen()
            onClick()
        },
    )
}
