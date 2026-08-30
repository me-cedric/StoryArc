package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ListPromotion
import app.storyarc.core.model.ReadingList
import kotlinx.coroutines.launch

/**
 * Choosing a server for a local reading list, and being told what the copy will do.
 *
 * `collections-and-reading-lists` asks the app to "offer to copy it" and to state "which
 * entries cannot be included because they do not exist on that server". Both happen here,
 * before anything is sent: the plan is on the sheet the reader confirms from, so nothing about
 * the copy is discovered afterwards.
 *
 * Only servers that answered the reading-list question are offered -- see
 * [LibraryViewModel.listServers]. A server that is not there is not on this sheet, which is
 * how the offer stays honest while the network is not. iOS's `PromoteListSheet` is the same
 * screen.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun PromoteListSheet(
    viewModel: LibraryViewModel,
    list: ReadingList,
    promoter: ListPromoter,
    onDismiss: () -> Unit,
    /**
     * Handed the undo when something reached the server, so the ten seconds are counted by
     * the same snackbar every other bulk action uses.
     */
    onCopied: (BulkUndo) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val scope = rememberCoroutineScope()
    val servers by viewModel.listServers.collectAsStateWithLifecycle()
    val publications by viewModel.publications.collectAsStateWithLifecycle()

    var chosen by remember { mutableStateOf<KavitaPage?>(null) }
    var isCopying by remember { mutableStateOf(false) }
    var hasFailed by remember { mutableStateOf(false) }

    // What each server would take, worked out once and keyed by the server. Once rather than
    // per redraw: every answer reads the origin note off disk for every entry. The copy works
    // the plan out again for itself, so what is sent can never be the stale copy of what was
    // shown.
    val plans = remember(servers, list) {
        servers.associate { it.id to promoter.plan(list, it) }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = palette.surfaceRaised) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            Text(
                text = stringResource(R.string.shelves_promote_title),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            Text(
                text = stringResource(R.string.shelves_promote_choose),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textSecondary,
            )

            servers.forEach { server ->
                val plan = plans[server.id] ?: ListPromotion(emptyList(), emptyList())
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { chosen = server }
                        .defaultMinSize(minHeight = 48.dp),
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = server.title,
                            style = MaterialTheme.typography.bodyLarge,
                            color = palette.textPrimary,
                        )
                        // The count is on the row itself, so the choice between two servers
                        // is made on what each of them can actually take.
                        Text(
                            text = stringResource(
                                R.string.shelves_promote_entries,
                                plan.copying.size,
                                plan.total,
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.textSecondary,
                        )
                    }
                    if (chosen?.id == server.id) {
                        Icon(
                            imageVector = Icons.Filled.Check,
                            contentDescription = null,
                            tint = palette.accent,
                        )
                    }
                }
            }

            chosen?.let { server ->
                Plan(
                    plan = plans[server.id] ?: ListPromotion(emptyList(), emptyList()),
                    server = server.title,
                    titleOf = { entry ->
                        publications.firstOrNull { it.id == entry }?.displayTitle ?: entry
                    },
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                modifier = Modifier.fillMaxWidth(),
            ) {
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.shelves_cancel))
                }
                TextButton(
                    enabled = !isCopying && chosen?.let { plans[it.id]?.isPossible } == true,
                    onClick = {
                        val server = chosen ?: return@TextButton
                        isCopying = true
                        scope.launch {
                            val undo = promoter.copy(list, server)
                            isCopying = false
                            if (undo == null) {
                                hasFailed = true
                            } else {
                                onCopied(undo)
                                onDismiss()
                            }
                        }
                    },
                ) {
                    Text(stringResource(R.string.shelves_promote_copy))
                }
            }
        }
    }

    if (hasFailed) {
        AlertDialog(
            onDismissRequest = { hasFailed = false },
            text = { Text(stringResource(R.string.shelves_promote_failed)) },
            confirmButton = {
                TextButton(onClick = { hasFailed = false }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

/** What the copy will do, stated before it happens. */
@Composable
private fun Plan(
    plan: ListPromotion,
    server: String,
    titleOf: (String) -> String,
) {
    val palette = LocalStoryArcPalette.current

    Text(
        text = stringResource(R.string.shelves_promote_plan),
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = Modifier.padding(top = StoryArcSpace.sm),
    )

    Text(
        text = if (plan.isPossible) {
            pluralStringResource(
                R.plurals.shelves_promote_copying,
                plan.copying.size,
                plan.copying.size,
            )
        } else {
            stringResource(R.string.shelves_promote_none, server)
        },
        style = MaterialTheme.typography.bodyMedium,
        color = palette.textPrimary,
    )

    if (plan.leftBehind.isNotEmpty()) {
        Text(
            text = pluralStringResource(
                R.plurals.shelves_promote_left_behind,
                plan.leftBehind.size,
                plan.leftBehind.size,
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        // Why, in the reader's terms rather than the protocol's: the app does not upload, so
        // a publication the server has never seen cannot join its list.
        Text(
            text = stringResource(R.string.shelves_promote_why, server),
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
        )
        // Named, not counted. A reader can only act on a title.
        plan.leftBehind.forEach { entry ->
            Text(
                text = titleOf(entry),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
}
