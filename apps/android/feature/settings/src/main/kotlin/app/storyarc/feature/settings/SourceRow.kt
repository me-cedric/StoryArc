package app.storyarc.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.zIndex
import app.storyarc.core.designsystem.control.MIN_TOUCH_TARGET
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.ImportedCopies
import java.util.UUID

/** The test tag of a row's drag handle. */
internal fun sourceDragHandleTag(source: Source) = "source-drag-handle-${source.id}"

/** The space between two rows, which a drag must cross as well as the row itself. */
internal val SOURCE_ROW_GAP = StoryArcSpace.md

/**
 * What a row of "Your libraries" offers, decided once so the menu, the drag handle and the
 * TalkBack actions cannot disagree. `close-the-audited-gaps` 27.3.
 *
 * The first and last rows cannot move further; one row cannot move at all; and "On this device"
 * is not a library the reader added, so it cannot be removed here.
 */
internal data class SourceRowActions(
    val canMoveEarlier: Boolean,
    val canMoveLater: Boolean,
    val canRemove: Boolean,
) {
    val canReorder: Boolean get() = canMoveEarlier || canMoveLater
}

internal fun sourceRowActions(index: Int, count: Int, sourceId: UUID) = SourceRowActions(
    canMoveEarlier = index > 0,
    canMoveLater = index < count - 1,
    canRemove = sourceId != ImportedCopies.SOURCE_ID,
)

/**
 * One library in the list: its name and state, one overflow menu, and a drag handle.
 *
 * Material 3 puts a row's secondary actions behind one overflow button and its order behind a
 * handle. Four icon buttons on one row left the name three lines tall and put remove beside
 * edit. The menu lists Move up, Move down and Rename, then a divider and Remove last, in the
 * error colour; Remove asks for confirmation in the caller's dialog. TalkBack reads the same
 * four actions off the row.
 *
 * @param onReorder moves the library one place: `true` later, `false` earlier. A drag calls it
 *   once for each row height the finger has travelled.
 */
@Composable
internal fun SourceRow(
    source: Source,
    index: Int,
    count: Int,
    itemCount: Int,
    isPartial: Boolean,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onRemove: () -> Unit,
    onReorder: (later: Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val actions = sourceRowActions(index, count, source.id)
    val moveEarlier = stringResource(R.string.sources_move_earlier, source.displayName)
    val moveLater = stringResource(R.string.sources_move_later, source.displayName)
    val rename = stringResource(R.string.sources_rename_action, source.displayName)
    val remove = stringResource(R.string.sources_remove_action, source.displayName)
    var dragOffset by remember { mutableFloatStateOf(0f) }
    var rowHeight by remember { mutableIntStateOf(0) }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = MIN_TOUCH_TARGET)
            .onSizeChanged { rowHeight = it.height }
            .zIndex(if (dragOffset != 0f) 1f else 0f)
            .graphicsLayer { translationY = dragOffset }
            .clickable(
                onClickLabel = stringResource(R.string.sources_detail_open, source.displayName),
                onClick = onOpen,
            )
            .semantics(mergeDescendants = true) {
                customActions = buildList {
                    if (actions.canMoveEarlier) add(CustomAccessibilityAction(moveEarlier) { onReorder(false); true })
                    if (actions.canMoveLater) add(CustomAccessibilityAction(moveLater) { onReorder(true); true })
                    add(CustomAccessibilityAction(rename) { onRename(); true })
                    if (actions.canRemove) add(CustomAccessibilityAction(remove) { onRemove(); true })
                }
            },
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon(source.kind), contentDescription = null, tint = palette.accentText)

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
        ) {
            Text(
                text = source.displayName,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            Text(
                text = stringResource(status(source.state)) + " · " +
                    pluralStringResource(
                        if (isPartial) R.plurals.sources_detail_partial else R.plurals.sources_detail,
                        itemCount,
                        itemCount,
                    ),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
            )
            if (source.kind == SourceKind.KAVITA_SERVER) {
                Text(
                    text = stringResource(R.string.sources_kavita_system_trust),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
            otherDeviceMark(source)?.let { mark ->
                Text(
                    text = stringResource(mark),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
        }

        SourceRowMenu(source, actions, onRename, onRemove, onReorder)

        if (actions.canReorder) {
            DragHandle(
                tag = sourceDragHandleTag(source),
                actions = actions,
                onReorder = onReorder,
                rowHeight = rowHeight,
                onOffset = { dragOffset = it },
            )
        }
    }
}

@Composable
private fun SourceRowMenu(
    source: Source,
    actions: SourceRowActions,
    onRename: () -> Unit,
    onRemove: () -> Unit,
    onReorder: (later: Boolean) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val error = MaterialTheme.colorScheme.error

    Box {
        IconButton(onClick = { open = true }) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.sources_menu_more, source.displayName),
                tint = LocalStoryArcPalette.current.textSecondary,
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (actions.canReorder) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.sources_menu_move_up)) },
                    leadingIcon = { Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null) },
                    enabled = actions.canMoveEarlier,
                    onClick = { open = false; onReorder(false) },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.sources_menu_move_down)) },
                    leadingIcon = { Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null) },
                    enabled = actions.canMoveLater,
                    onClick = { open = false; onReorder(true) },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.sources_menu_rename)) },
                leadingIcon = { Icon(Icons.Filled.Edit, contentDescription = null) },
                onClick = { open = false; onRename() },
            )
            if (actions.canRemove) {
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.sources_remove), color = error) },
                    leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null, tint = error) },
                    onClick = { open = false; onRemove() },
                )
            }
        }
    }
}

/**
 * The grip at the end of a row. A vertical drag moves the library one place for each row height
 * the finger travels, and the row follows the finger by the part of a step it has not yet taken.
 *
 * It carries no label and no click action: TalkBack reorders through the row's own actions, and
 * a control that only a drag can use would be one that screen-reader users cannot reach.
 */
@Composable
private fun DragHandle(
    tag: String,
    actions: SourceRowActions,
    onReorder: (later: Boolean) -> Unit,
    rowHeight: Int,
    onOffset: (Float) -> Unit,
) {
    val current by rememberUpdatedState(actions)
    val reorder by rememberUpdatedState(onReorder)
    val height by rememberUpdatedState(rowHeight)

    Box(
        modifier = Modifier
            .size(MIN_TOUCH_TARGET)
            .pointerInput(Unit) {
                var travelled = 0f
                detectVerticalDragGestures(
                    onDragStart = { travelled = 0f },
                    onDragEnd = { travelled = 0f; onOffset(0f) },
                    onDragCancel = { travelled = 0f; onOffset(0f) },
                ) { change, delta ->
                    change.consume()
                    val step = height + SOURCE_ROW_GAP.toPx()
                    travelled += delta
                    if (travelled > step && current.canMoveLater) {
                        reorder(true)
                        travelled -= step
                    } else if (travelled < -step && current.canMoveEarlier) {
                        reorder(false)
                        travelled += step
                    }
                    onOffset(travelled)
                }
            }
            .clearAndSetSemantics { testTag = tag },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.DragHandle,
            contentDescription = null,
            tint = LocalStoryArcPalette.current.textSecondary,
        )
    }
}
