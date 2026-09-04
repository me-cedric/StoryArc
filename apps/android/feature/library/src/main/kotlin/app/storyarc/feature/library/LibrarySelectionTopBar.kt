package app.storyarc.feature.library

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.BulkSelection
import kotlinx.coroutines.launch

/**
 * What can be done to everything the reader has picked — as a **contextual top app bar**.
 *
 * **This replaces a bottom slab, and the bottom was never Android's to spend.**
 * `BulkActionBar` drew a `Surface` of `surfaceRaised` across the foot of the shelf holding a
 * count, three `IconButton`s and a *Done*. That was a translation of what iOS was doing, and
 * iOS was doing it wrong too: the owner's report — "the current selection bar is not a modern
 * way of doing this" — was about a shape, and this platform's answer to that shape is a
 * different shape again.
 *
 * On Android the foot of the window already belongs to the navigation bar, and
 * `native-experience` asks each app to follow "that platform's current design language".
 * Material 3 Expressive's answer to a selection mode is the contextual top app bar: a close
 * affordance at the start, the count as the title, the actions as top-bar actions with an
 * overflow. So the navigation bar is untouched for the whole of the mode, and the bar that
 * changes is the one at the top.
 *
 * **This diverges from iOS deliberately, and ADR-0001 is the licence.** iOS *hides* its tab
 * bar for the duration and floats a glass capsule where the tab bar was, because that is
 * what Photos, Files and Mail do there. Doing the same here would be putting an iOS answer
 * on an Android window: a floating bar over the gesture area, with the navigation bar
 * missing from a screen a reader has not left. Same requirement, two idioms.
 *
 * **Which actions are glyphs, and which is named.** *Download* and *Mark as read* are icon
 * actions: a downward arrow and a check are glyphs a reader already knows, and a top app
 * bar's action slot has no room for a word at any width — that is the platform's constraint
 * rather than a preference. *Add to…* is an overflow row with its name showing, because
 * `PlaylistAdd` is exactly the sort of glyph the design review of 2026-09-01 objected to,
 * and because the action opens a chooser rather than doing something: a named row leading to
 * a sheet is the honest shape. All three carry a `contentDescription` unconditionally.
 *
 * The three go inert together when nothing is picked, and are drawn rather than hidden —
 * the same answer iOS gives, for the same reason: controls that arrive on the first pick
 * are controls that move under a thumb. The way out is *not* in that group. It is the close
 * affordance at the start, live throughout, because the reader who picked nothing is the one
 * who most needs to leave.
 *
 * `BulkSelectionChromeTest` composes this and asks it every one of those questions.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibrarySelectionTopBar(
    selection: LibrarySelection,
    onSelectionChange: (LibrarySelection) -> Unit,
    /** Opens the add-to sheet over the whole selection. The screen hosts it. */
    onAddToShelf: () -> Unit,
    /** Asks to download the selection. The screen owns the confirmation — see [BulkDownloadPrompt]. */
    onDownload: () -> Unit,
    /**
     * Marks the selection read. The screen does it, because marking also tells the server a
     * publication came from and the app layer is what holds that server's secrets.
     */
    onMarkRead: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val enabled = selection.ids.isNotEmpty()

    TopAppBar(
        title = {
            Text(
                text = pluralStringResource(
                    R.plurals.library_selected,
                    selection.count,
                    selection.count,
                ),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        },
        colors = TopAppBarDefaults.topAppBarColors(
            // The raised surface rather than the canvas the library's own bar sits on. A
            // contextual bar that looked identical to the one it replaced would be a mode
            // change a reader could miss, and Material asks the selection bar to read as a
            // different bar rather than the same one with different buttons.
            containerColor = palette.surfaceRaised,
            scrolledContainerColor = palette.surfaceRaised,
            titleContentColor = palette.textPrimary,
        ),
        navigationIcon = {
            // The one control that is never disabled, so an explicit tint is safe here and
            // only here. The way out of a mode does not dim.
            IconButton(onClick = { onSelectionChange(selection.end()) }) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.library_select_stop),
                    tint = palette.accent,
                )
            }
        },
        actions = {
            // **The accent arrives as the button's content colour, not as the icon's tint.**
            // These three carry `enabled`, and an `IconButton` shows a disabled child by
            // lowering `LocalContentColor` — which an `Icon` that passes `tint = palette.accent`
            // never reads. So `enabled = false` dimmed nothing: cropping the action region from
            // the nought-picked and two-picked captures of 2026-09-04 gave **byte-identical**
            // PNGs, and a reader saw three controls drawn exactly as live as the live ones,
            // two of which do nothing.
            //
            // `iconButtonColors(contentColor:)` hands the dimming back to Material, which
            // derives the disabled colour from the one given rather than from a hard-coded
            // alpha of ours — so the accent still leads and the disabled treatment stays
            // whatever the platform's current answer is. iOS had the same defect from the
            // mirror-image cause: an explicit `foregroundStyle` there overriding the dimming
            // `.disabled` applies. Same rule, both platforms: state the colour where the
            // control can still take it away.
            IconButton(
                onClick = onDownload,
                enabled = enabled,
                colors = IconButtonDefaults.iconButtonColors(contentColor = palette.accent),
            ) {
                Icon(
                    imageVector = Icons.Filled.Download,
                    contentDescription = stringResource(R.string.library_bulk_download),
                )
            }
            // **Mark-as-read is in the overflow, not the bar, and the reason is one frame
            // away.** `PickMark` draws a picked cover as `Icons.Filled.CheckCircle` tinted
            // `palette.accent` — the same vector, the same tint — so a bar action drawn that
            // way is the picked state's own mark asked to mean something else, four rows
            // below dozens of it. `native-experience`'s *Every action names itself* refuses
            // exactly that: a mark another control in the same frame already uses is not
            // established here, whatever it means elsewhere.
            //
            // iOS reached the same verdict about `checkmark.circle` on its own capsule, where
            // the case was *weaker* — a ring-with-a-check is the visual union of the picked
            // disc and the unpicked ring rather than the picked mark itself — and answered it
            // by keeping the word beside the glyph wherever a word fits. A top app bar's
            // action slot has no room for a word at any width, so this platform's answer to
            // the same rule is the overflow, where the name is drawn in full.
            SelectionOverflowMenu(
                enabled = enabled,
                onAddToShelf = onAddToShelf,
                onMarkRead = onMarkRead,
            )
        },
    )
}

/**
 * The action whose glyph would lie, named in words.
 *
 * Two rows, and both are here for the same reason rather than to shorten the bar: an action
 * whose glyph would lie wants a name, and a top app bar's action slot has no room for a word at
 * any width. `PlaylistAdd` gives a reader neither a name nor a readable symbol. `CheckCircle`
 * is worse than unreadable — it is the mark `PickMark` puts on every picked cover in the same
 * frame, so in the bar it asks one symbol to mean *picked* and *mark as read* at once.
 *
 * [LibraryOverflowMenu] does the same thing for the library's own bar, and this is where a
 * fourth bulk action — copying a list to a server, say — would land without turning the bar
 * into a row of glyphs again.
 */
@Composable
private fun SelectionOverflowMenu(
    enabled: Boolean,
    onAddToShelf: () -> Unit,
    onMarkRead: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    IconButton(
        onClick = { open = true },
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(contentColor = palette.accent),
    ) {
        Icon(
            imageVector = Icons.Filled.MoreVert,
            contentDescription = stringResource(R.string.library_more),
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_mark_read)) },
            leadingIcon = { Icon(Icons.Filled.CheckCircle, contentDescription = null) },
            onClick = {
                open = false
                onMarkRead()
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.shelves_add_to)) },
            leadingIcon = {
                Icon(Icons.AutoMirrored.Filled.PlaylistAdd, contentDescription = null)
            },
            onClick = {
                open = false
                onAddToShelf()
            },
        )
    }
}

/**
 * What a bulk download would copy, and what it weighs, asked before anything is copied.
 *
 * `offline-downloads`: the app "states the item count and total size and asks for confirmation
 * before queueing them" — and `collections-and-reading-lists` asks the same of a selection.
 * Both dialogs stood inside the old bottom bar. They are here rather than inside
 * [LibrarySelectionTopBar] because that composable is a `Scaffold`'s `topBar` slot, and a slot
 * measured for the height of a bar is not a place to open a window from.
 *
 * Driven by [requested] rather than by a tap of its own: the tap is in the bar, the work is
 * here, and the two are joined by one boolean the screen holds. What the download would copy
 * is worked out when the reader asks, not on every recomposition — both halves read the
 * download store off disk.
 */
@Composable
internal fun BulkDownloadPrompt(
    viewModel: LibraryViewModel,
    selection: LibrarySelection,
    requested: Boolean,
    onSettled: () -> Unit,
    /** What the download changed, so the screen can offer one undo for the set. */
    onChange: (BulkUndo) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    if (!requested) return

    val wanted = remember(selection.ids) {
        BulkSelection.downloading(selection.ids, viewModel.keptOffline())
    }

    if (wanted.isEmpty()) {
        AlertDialog(
            onDismissRequest = onSettled,
            text = { Text(stringResource(R.string.library_bulk_download_none)) },
            confirmButton = {
                TextButton(onClick = onSettled) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
        return
    }

    val bytes = remember(wanted) { viewModel.bytesOnDisk(wanted) }
    AlertDialog(
        onDismissRequest = onSettled,
        title = {
            Text(
                pluralStringResource(
                    R.plurals.library_bulk_download_title,
                    wanted.size,
                    wanted.size,
                ),
            )
        },
        text = {
            Text(
                stringResource(
                    R.string.library_bulk_download_size,
                    android.text.format.Formatter.formatFileSize(context, bytes),
                ),
            )
        },
        confirmButton = {
            TextButton(onClick = {
                onSettled()
                scope.launch {
                    onChange(BulkUndo(BulkUndo.Kind.Kept, viewModel.keepOffline(wanted)))
                }
            }) {
                Text(stringResource(R.string.library_bulk_download))
            }
        },
        dismissButton = {
            TextButton(onClick = onSettled) {
                Text(stringResource(R.string.shelves_cancel))
            }
        },
    )
}
