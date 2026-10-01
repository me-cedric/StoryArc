package app.storyarc.feature.library

import android.content.Intent
import android.net.Uri
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import kotlinx.coroutines.flow.update

/** Gives a folder's persisted read permission back, if the system still grants one. */
internal fun LibraryViewModel.releaseFolderGrant(tree: Uri) {
    runCatching {
        resolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}

/**
 * 10.13: a re-pick under the same [name] retires whatever stale, unreachable row it
 * replaces -- the grant goes back and the row goes, so neither comes back at the next
 * launch the way `addFolder` clearing `unavailableFolders` for this session only could not
 * promise. [locator] is the tree just registered, so its own row is never the one retired.
 */
internal fun LibraryViewModel.retireStaleFolderRows(name: String, locator: String) {
    _registry.value.sources
        .filter {
            it.kind == SourceKind.LOCAL_FOLDER && it.locator != locator &&
                it.displayName == name && it.state is SourceConnectionState.Unreachable
        }
        .forEach { stale ->
            stale.locator?.let(Uri::parse)?.let(::releaseFolderGrant)
            _registry.update { it.discarding(stale.id) }
            _publications.update { list -> list.filterNot { it.sourceId == stale.id } }
        }
}

/**
 * Writes the shelf through immediately, rather than leaving it for the next scan.
 * `cacheLibrary` refuses to replace a good snapshot with an empty one -- that guard is there
 * for a walk that failed, and this is not one, so an emptied shelf clears the file outright.
 * Shared by `clearSourceCache` and `forget` (10.15): neither wrote the snapshot through, so
 * a removed source's rows came back from the cached shelf at the next launch.
 */
internal fun LibraryViewModel.writeShelfThrough() {
    if (_publications.value.isEmpty()) shelfCache.clear() else cacheLibrary()
    shelfCache.forgetTheMoment()
}
