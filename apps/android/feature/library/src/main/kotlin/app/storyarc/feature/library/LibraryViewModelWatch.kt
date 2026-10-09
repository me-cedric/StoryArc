package app.storyarc.feature.library

import android.net.Uri
import androidx.lifecycle.viewModelScope
import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.SafTree
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The watched folders, and what a change in one of them re-reads.
//
// Moved out of `LibraryViewModel.kt` unchanged, as extensions on the view model, so that
// file stays under the 800-line cap. The state these read stays on the class.

/**
 * Watches every folder the reader added.
 *
 * Called whenever the set of folders changes, which is the only thing that invalidates
 * what is being watched.
 */
internal fun LibraryViewModel.startWatching() {
    if (_folders.value.isEmpty()) {
        watcher.stop()
        return
    }
    watcher.watch(_folders.value) { reconcileWatchedFolders() }
}

/** Stops watching. The library stays; only the registrations go. */
fun LibraryViewModel.stopWatching() {
    watcher.stop()
}

/** Brings every watched folder up to date, and re-checks that each can still be read. */
fun LibraryViewModel.reconcileWatchedFolders() {
    val restored = SafTree.persistedTrees(resolver)
    refreshFolderAvailability(restored, restored.filter { SafTree.displayName(resolver, it) != null })
    val trees = _folders.value
    if (trees.isEmpty()) return
    viewModelScope.launch {
        for (tree in trees) reconcile(tree)
    }
}

/**
 * Notices what changed in one folder, and re-reads only that: nothing, in the common
 * case of an unchanged listing, and nothing while it has no snapshot yet either -- the
 * running scan owns that one, and an empty fallback used to report every file as added.
 */
private suspend fun LibraryViewModel.reconcile(tree: Uri) {
    val snapshot = snapshots[tree.toString()].takeIf(::mayReconcile) ?: return
    val listing = withContext(Dispatchers.IO) { LibraryScanner.listing(resolver, tree) }
    val walked = listing.map { it.entry }
    // Null means the walk found nothing where something used to be -- an unreadable
    // folder far more often than a reader who deleted every book. Nothing is removed and
    // the snapshot is left alone; see `FolderSnapshot.change`.
    val change = snapshot.change(walked) ?: return
    if (change.isEmpty) return

    val sourceId = sourceOf(tree)
    // A changed file is re-read from scratch rather than patched: its series, its page
    // count and its cover can all have moved, and there is no cheaper honest answer.
    for (path in change.removed + change.changed.map { it.path }) forget(path)

    val byPath = listing.associateBy { it.entry.path }
    for (entry in change.toIndex) {
        val listed = byPath[entry.path] ?: continue
        val publication = withContext(Dispatchers.IO) {
            runCatching { LibraryScanner.index(resolver, tree, listed, audiobookCoverCacheDir) }.getOrNull()
        } ?: continue
        adopt(publication, sourceId)
        locations[publication.id] = entry.path
    }

    snapshots[tree.toString()] = snapshot.updated(walked)
    rebuild()
    refreshProgress()
}

/**
 * Drops the row for a file that has gone or has been replaced.
 *
 * By path rather than by identity, because the path is the only thing a directory
 * listing knows -- and it is what [locations] is keyed on for exactly this.
 */
private fun LibraryViewModel.forget(path: String) {
    val gone = locations.filterValues { it == path }.keys.toSet()
    if (gone.isEmpty()) return
    _publications.update { current -> current.filterNot { it.id in gone } }
    locations.keys.removeAll(gone)
}
