package app.storyarc.feature.library

import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.PublicationIdentity
import java.net.URLDecoder

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

    /** Adds what one sync found to the notice. None adds nothing. */
    fun report(found: List<ProgressPull.Conflict>) {
        RefreshConflicts.report(found.map(::notice))
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

    internal fun title(identity: PublicationIdentity): String {
        val path = identity.normalizedPath.orEmpty()
        val decoded = runCatching { URLDecoder.decode(path.replace("+", "%2B"), "UTF-8") }.getOrDefault(path)
        val leaf = decoded.substringAfterLast('/').substringAfterLast(':')
        val dot = leaf.lastIndexOf('.')
        return if (dot > 0) leaf.substring(0, dot) else leaf
    }
}
