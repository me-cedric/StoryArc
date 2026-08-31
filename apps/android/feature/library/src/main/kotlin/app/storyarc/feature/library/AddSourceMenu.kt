package app.storyarc.feature.library

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette

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
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = stringResource(R.string.library_add_source),
            tint = palette.accent,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_add_folder)) },
            leadingIcon = { Icon(Icons.Filled.CreateNewFolder, contentDescription = null) },
            onClick = {
                open = false
                onAddFolder()
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_import)) },
            leadingIcon = { Icon(Icons.Filled.FileDownload, contentDescription = null) },
            onClick = {
                open = false
                onImport()
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.catalogue_title)) },
            leadingIcon = { Icon(Icons.Filled.RssFeed, contentDescription = null) },
            onClick = {
                open = false
                onAddCatalogue()
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.kavita_title)) },
            leadingIcon = { Icon(Icons.Filled.Dns, contentDescription = null) },
            onClick = {
                open = false
                onAddKavita()
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.smb_title)) },
            leadingIcon = { Icon(Icons.Filled.Storage, contentDescription = null) },
            onClick = {
                open = false
                onAddShare()
            },
        )
    }
}
