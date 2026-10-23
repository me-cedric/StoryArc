package app.storyarc.feature.library

import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.leafTitle
import app.storyarc.core.persistence.LibrarySyncState

/**
 * The conflicts a library sync found, handed to the notice a refresh already shows.
 *
 * `library-sync` task 5.4. The sync merges positions by ADR-0006 and returns each title both
 * devices had moved. The runner used to drop them, so the reader never saw D3's notice. They go
 * to [RefreshConflicts], which the library screen draws as [SyncConflictNotice]: one title names
 * the kept and the discarded position, several give a count and Show. iOS's `SyncConflicts` is
 * the same step.
 */
object SyncConflicts {

    /**
     * Where a sync's conflicts wait for the reader, or null in a process that wired none.
     *
     * Task 5.9: a background sync runs in a process with no screen, and a notice held only
     * in [RefreshConflicts] went with that process. What a sync finds is written here too,
     * [restore] shows it again in the next process, and the reader's answer clears it.
     */
    @Volatile
    var pending: LibrarySyncState? = null

    /** Adds what one sync found to the notice, and keeps it until the reader answers. None adds nothing. */
    fun report(found: List<ProgressPull.Conflict>) {
        if (found.isEmpty()) return
        pending?.let { it.savePendingConflicts(it.pendingConflicts() + found) }
        RefreshConflicts.report(found.map(::notice))
    }

    /** Shows what earlier processes found and nobody answered. Once, when the runner is built. */
    fun restore() {
        RefreshConflicts.report(pending?.pendingConflicts().orEmpty().map(::notice))
    }

    /** The reader kept or took a position: nothing waits any more. */
    fun answered() {
        pending?.savePendingConflicts(emptyList())
    }

    /**
     * One conflict as the notice names it. The sync document carries no title, so the title is
     * the file's name without its extension, as a folder scan names a publication.
     */
    internal fun notice(conflict: ProgressPull.Conflict) = KavitaConflict(
        title = title(conflict.resolved.identity),
        resolved = conflict.resolved,
        discarded = conflict.discarded,
    )

    internal fun title(identity: PublicationIdentity): String = identity.leafTitle
}
