package app.storyarc.feature.library

import android.net.Uri
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.ImportedCopies

/**
 * Which folder sources a restore or a resume finds unreachable, decided without a
 * `ContentResolver`.
 *
 * `local-library`: a folder whose access the system no longer grants is marked
 * `Unreachable` and named, rather than left in whatever state it loaded with. Only a tree
 * [SafTree.persistedTrees] still lists *and* can resolve a display name for counts as
 * reachable here — everything else is a folder the app cannot open, whether the grant
 * survived with a dead provider behind it or vanished outright, and both read the same to
 * a reader: the folder is gone.
 *
 * A value rather than a sequence of statements inside the view model, so the registry it
 * is asked to update can be asserted without an Android runtime. [SourceRemoval] is the
 * same shape for the same reason.
 */
internal data class FolderAvailability(
    /** The registry with every folder source marked as its tree now answers, unchanged otherwise. */
    val registry: SourceRegistry,
    /** The folder sources this pass marked unreachable, for naming in `unavailableFolders`. */
    val newlyUnreachable: List<Source>,
) {
    companion object {
        fun of(
            registry: SourceRegistry,
            reachableLocators: Set<String>,
            atEpochMillis: Long,
        ): FolderAvailability {
            // Not "On this device": its locator is no tree anyone picked, so it is never
            // among the reachable trees, and marking it would grey every imported copy.
            val unreachable = registry.sources.filter {
                it.kind == SourceKind.LOCAL_FOLDER && it.id != ImportedCopies.SOURCE_ID &&
                    it.locator !in reachableLocators
            }
            // And back: a tree that answers again, a card put back in, is connected again on
            // the next resume rather than grey until the next launch.
            val recovered = registry.sources.filter {
                it.kind == SourceKind.LOCAL_FOLDER && it.locator in reachableLocators &&
                    it.state is SourceConnectionState.Unreachable
            }
            if (unreachable.isEmpty() && recovered.isEmpty()) return FolderAvailability(registry, emptyList())
            val marked = unreachable.fold(registry) { acc, source ->
                acc.marking(source.id, SourceConnectionState.Unreachable(atEpochMillis), atEpochMillis)
            }
            val answered = recovered.fold(marked) { acc, source ->
                acc.marking(source.id, SourceConnectionState.Connected, atEpochMillis)
            }
            return FolderAvailability(answered, unreachable)
        }
    }
}

/**
 * Marks every `LOCAL_FOLDER` source whose tree is not in [reachable] as `Unreachable`, and
 * names it beside whatever [restored] could not resolve a display name for.
 *
 * Called at restore and on every resume ([LibraryViewModel.reconcileWatchedFolders]),
 * because access can be revoked while the app is in the background and nothing else
 * re-asks a folder that is not being walked or watched.
 */
internal fun LibraryViewModel.refreshFolderAvailability(restored: List<Uri>, reachable: List<Uri>) {
    val availability = FolderAvailability.of(
        _registry.value,
        reachable.map { it.toString() }.toSet(),
        System.currentTimeMillis(),
    )
    if (availability.registry != _registry.value) {
        _registry.value = availability.registry
        sourceStore?.save(availability.registry)
    }
    val unreachableTreeNames = (restored - reachable.toSet()).map { nameOf(it) }
    _unavailableFolders.value =
        (unreachableTreeNames + availability.newlyUnreachable.map { it.displayName }).distinct()
}
