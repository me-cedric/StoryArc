package app.storyarc.feature.library

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.CloudUpload
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
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
import androidx.compose.ui.res.stringResource

/** The five things a reader can do about a cover, in the order the menu lists them. */
internal enum class CoverAction { CHOOSE, FIND, WEB, SEND, REMOVE }

/**
 * What a cover's menu can do, one handler per row; a null handler is a row that is not drawn.
 *
 * Task 24.1 of `close-the-audited-gaps`. Three stacked text buttons were each as tall as
 * their text, and a finger hit the wrong one. One menu gives every row Material's 48 dp, and
 * [groups] is where "which rows, in which groups" is decided, so a test can state the rule
 * without opening a popup. iOS's `CoverMenu` is its twin.
 */
internal data class CoverMenu(
    val onChoose: (() -> Unit)? = null,
    val onFind: (() -> Unit)? = null,
    val onWeb: (() -> Unit)? = null,
    val onSend: (() -> Unit)? = null,
    val onRemove: (() -> Unit)? = null,
) {
    fun handler(action: CoverAction): (() -> Unit)? = when (action) {
        CoverAction.CHOOSE -> onChoose
        CoverAction.FIND -> onFind
        CoverAction.WEB -> onWeb
        CoverAction.SEND -> onSend
        CoverAction.REMOVE -> onRemove
    }

    /**
     * The rows that exist, grouped for dividers.
     *
     * Every way of setting a cover is one group. Removal is the last row, alone in its own
     * group, because it is the one row that destroys something.
     */
    fun groups(): List<List<CoverAction>> = listOf(
        listOf(CoverAction.CHOOSE, CoverAction.FIND, CoverAction.WEB, CoverAction.SEND),
        listOf(CoverAction.REMOVE),
    ).map { group -> group.filter { handler(it) != null } }.filter { it.isNotEmpty() }
}

/**
 * The page's cover choice as a menu.
 *
 * Nothing at all where the page offers no choice, which is what keeps a test's hero the hero
 * it was. The title search is a row only while [CoverFinderOffer.findACover] holds, and the
 * web search only where there is a title to search for.
 */
internal fun CoverChoice.menu(onSend: (() -> Unit)? = null): CoverMenu {
    if (onChoose == null) return CoverMenu()
    val found = finder
    val web = found?.takeIf { it.offer.webSearch }
        ?.let { CoverSearchHandoff.intent(it.title, it.author) }
    return CoverMenu(
        onChoose = onChoose,
        onFind = found?.takeIf { it.offer.findACover }?.onFind,
        onWeb = web?.let { intent -> { found.onOpenWeb(intent) } },
        onSend = onSend,
        onRemove = onRemove,
    )
}

/**
 * A cover, with one edit button on its bottom corner and a long press, both opening [menu].
 *
 * **One menu, not a row of buttons.** Material 3 asks for a touch target of 48 dp with 8 dp
 * between targets, and a menu is the idiom for a list of related actions: the system draws
 * each row at full height and a divider separates the groups. The button is
 * `FilledTonalIconButton`, whose 40 dp circle keeps a 48 dp target through
 * `minimumInteractiveComponentSize`.
 *
 * **The removal asks first.** The chosen picture is deleted from the device, so the remove
 * row opens an [AlertDialog] that says so; dismissing it changes nothing.
 *
 * [open] and [onOpenChange] are the caller's, so a label elsewhere on the page ("Add a
 * cover") can open the same menu. [accent] keeps the 3:1 rule [CoverChoiceControls] documents:
 * the button is the page's own wash with the accent on it, the one pair the page guarantees.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun CoverActionsHost(
    menu: CoverMenu,
    open: Boolean,
    onOpenChange: (Boolean) -> Unit,
    accent: DetailAccent?,
    modifier: Modifier = Modifier,
    cover: @Composable () -> Unit,
) {
    val groups = menu.groups()
    if (groups.isEmpty()) {
        Box(modifier) { cover() }
        return
    }
    val edit = stringResource(R.string.cover_edit)
    var confirmingRemove by remember { mutableStateOf(false) }
    Box(modifier) {
        // A sibling of the button rather than its parent: a clickable merges its descendants
        // into one node, which would fold the button's own label and action into the cover's.
        Box(
            Modifier.combinedClickable(
                onClickLabel = edit,
                onClick = { onOpenChange(true) },
                onLongClickLabel = edit,
                onLongClick = { onOpenChange(true) },
            ),
        ) { cover() }
        FilledTonalIconButton(
            onClick = { onOpenChange(true) },
            modifier = Modifier.align(Alignment.BottomEnd),
            colors = accent?.let {
                IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = it.wash,
                    contentColor = it.accent,
                )
            } ?: IconButtonDefaults.filledTonalIconButtonColors(),
        ) {
            Icon(Icons.Outlined.Edit, contentDescription = edit)
        }
        DropdownMenu(expanded = open, onDismissRequest = { onOpenChange(false) }) {
            groups.forEachIndexed { index, group ->
                if (index > 0) HorizontalDivider()
                group.forEach { action ->
                    CoverMenuRow(action) {
                        onOpenChange(false)
                        if (action == CoverAction.REMOVE) confirmingRemove = true else menu.handler(action)?.invoke()
                    }
                }
            }
        }
    }
    if (confirmingRemove) {
        AlertDialog(
            onDismissRequest = { confirmingRemove = false },
            title = { Text(stringResource(R.string.cover_remove_title)) },
            text = { Text(stringResource(R.string.cover_remove_body)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingRemove = false
                    menu.onRemove?.invoke()
                }) {
                    Text(stringResource(R.string.cover_remove))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingRemove = false }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

@Composable
private fun CoverMenuRow(action: CoverAction, onClick: () -> Unit) {
    val destructive = action == CoverAction.REMOVE
    val error = MaterialTheme.colorScheme.error
    DropdownMenuItem(
        text = {
            Column {
                Text(stringResource(action.label))
                // What the hand-off does, said where the reader chooses it: the browser
                // searches, StoryArc downloads nothing.
                if (action == CoverAction.WEB) {
                    Text(
                        text = stringResource(R.string.covers_web_note),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        leadingIcon = { Icon(action.icon, contentDescription = null) },
        // The one row that leaves the app says so, as Material marks a link out.
        trailingIcon = if (action == CoverAction.WEB) {
            { Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null) }
        } else {
            null
        },
        colors = if (destructive) {
            MenuDefaults.itemColors(
                textColor = error,
                leadingIconColor = error,
            )
        } else {
            MenuDefaults.itemColors()
        },
        onClick = onClick,
    )
}

private val CoverAction.label: Int
    get() = when (this) {
        CoverAction.CHOOSE -> R.string.cover_pick
        CoverAction.FIND -> R.string.covers_find
        CoverAction.WEB -> R.string.covers_web_search
        CoverAction.SEND -> R.string.covers_write_back
        CoverAction.REMOVE -> R.string.cover_remove
    }

private val CoverAction.icon: ImageVector
    get() = when (this) {
        CoverAction.CHOOSE -> Icons.Outlined.PhotoLibrary
        CoverAction.FIND -> Icons.Outlined.Search
        CoverAction.WEB -> Icons.Outlined.Language
        CoverAction.SEND -> Icons.Outlined.CloudUpload
        CoverAction.REMOVE -> Icons.Outlined.Delete
    }
