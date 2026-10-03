package app.storyarc.feature.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch

/**
 * [SyncConflictNotice] for a conflict a Kavita source's own background refresh found, rather
 * than the series screen's own pull -- task 2.9. One mount for the whole library screen, since
 * a refresh walks every configured source in one pass and D3 asks for one notice naming
 * whatever it found, not one dialog per source.
 */
@Composable
internal fun RefreshConflictNotice(viewModel: LibraryViewModel?) {
    val scope = rememberCoroutineScope()
    val conflicts by RefreshConflicts.conflicts.collectAsStateWithLifecycle()
    SyncConflictNotice(
        conflicts = conflicts,
        onKeep = { RefreshConflicts.clear() },
        onTake = { discarded ->
            RefreshConflicts.clear()
            val progress = viewModel?.progressStore ?: return@SyncConflictNotice
            scope.launch {
                discarded.forEach { conflict -> progress.save(conflict.resolved.copy(position = conflict.discarded)) }
            }
        },
    )
}
