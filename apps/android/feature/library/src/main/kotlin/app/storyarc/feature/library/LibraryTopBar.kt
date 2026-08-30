package app.storyarc.feature.library

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MediumFlexibleTopAppBar
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette

/**
 * The library's top bar.
 *
 * **This replaces a bar that had eight action icons in it and no room left for its own
 * title.** At 411 dp the word "Library" was squeezed into a column one letter wide; at
 * 320 dp it disappeared and the last control was pushed off the screen. That was a defect
 * rather than a matter of taste — a title a reader cannot read and a control they cannot
 * reach — and Material has the answer to it in two parts, both used here.
 *
 * The first is the **flexible bar**: [MediumFlexibleTopAppBar] gives the title a row of its
 * own under the actions, so no number of icons can crowd it, and the same bar carries the
 * large editorial title the design direction asks of every destination. The second is the
 * **overflow menu**: what a reader touches on most visits — the availability axis, sort,
 * filter, layout — moves out to [LibraryControls] under the bar, and everything that is
 * occasional goes behind one `⋮`.
 *
 * The bar collapses as the shelf scrolls under it (`exitUntilCollapsedScrollBehavior`,
 * supplied by the caller), which is Android's answer to getting chrome out of the artwork's
 * way — §4.3 of the design direction, and the reason there is no pinned bar here any more.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibraryTopBar(
    scrollBehavior: TopAppBarScrollBehavior,
    onAddFolder: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
    onImport: () -> Unit,
    /** Begins a bulk selection. Null while there is nothing to select, or already selecting. */
    onSelect: (() -> Unit)?,
    /** Null on a window wide enough that the navigation rail already carries collections. */
    onOpenShelves: (() -> Unit)?,
    /** Null on a window wide enough that the navigation rail already carries settings. */
    onOpenSettings: (() -> Unit)?,
) {
    val palette = LocalStoryArcPalette.current

    MediumFlexibleTopAppBar(
        title = {
            Text(
                text = stringResource(R.string.library_title),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = palette.surfaceCanvas,
            scrolledContainerColor = palette.surfaceRaised,
            titleContentColor = palette.textPrimary,
        ),
        scrollBehavior = scrollBehavior,
        actions = {
            // Adding stays a button of its own rather than an item in the overflow: it is
            // the one thing an almost-empty library is for, and a reader who has just
            // installed the app should not have to find it behind a menu.
            AddSourceMenu(
                onAddFolder = onAddFolder,
                onAddCatalogue = onAddCatalogue,
                onAddKavita = onAddKavita,
                onAddShare = onAddShare,
                onImport = onImport,
            )
            LibraryOverflowMenu(
                onSelect = onSelect,
                onOpenShelves = onOpenShelves,
                onOpenSettings = onOpenSettings,
            )
        },
    )
}

/**
 * Everything the bar used to spend an icon on and a reader touches once a week.
 *
 * Absent rather than empty: on a wide window the rail already carries collections and
 * settings, and a library with nothing in it has nothing to select — at which point a `⋮`
 * that opens an empty menu is worse than no `⋮` at all.
 */
@Composable
private fun LibraryOverflowMenu(
    onSelect: (() -> Unit)?,
    onOpenShelves: (() -> Unit)?,
    onOpenSettings: (() -> Unit)?,
) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    if (onSelect == null && onOpenShelves == null && onOpenSettings == null) return

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.MoreVert,
            contentDescription = stringResource(R.string.library_more),
            tint = palette.accent,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        onSelect?.let { select ->
            OverflowItem(
                label = stringResource(R.string.library_select),
                icon = Icons.Filled.Checklist,
            ) {
                open = false
                select()
            }
        }
        onOpenShelves?.let { shelves ->
            OverflowItem(
                label = stringResource(R.string.shelves_title),
                icon = Icons.Filled.Inventory2,
            ) {
                open = false
                shelves()
            }
        }
        onOpenSettings?.let { settings ->
            OverflowItem(
                label = stringResource(R.string.library_settings),
                icon = Icons.Filled.Settings,
            ) {
                open = false
                settings()
            }
        }
    }
}

@Composable
private fun OverflowItem(
    label: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        onClick = onClick,
    )
}
