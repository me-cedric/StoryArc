package app.storyarc.core.model

import java.util.UUID

/**
 * Which of two sources holding the same publication the library shows.
 *
 * `sources`: when a reader reorders their sources, "the library's combined view lists titles
 * from higher sources first when two sources hold the same publication". The order persisted;
 * nothing read it. Whichever scan happened to reach a title first kept it, so dragging a
 * source to the top changed the list in Settings and changed nothing else.
 *
 * A pure answer rather than a rule buried in the scan, because it is a comparison over the
 * registry and has no business needing a filesystem to assert. iOS's `SourcePrecedence` ranks
 * the same three cases the same way.
 */
object SourcePrecedence {

    /**
     * Where a source stands. Lower wins, and everything unknown ties for last.
     *
     * Two things rank last, deliberately and identically. A publication with no source at all
     * was found in the app's own folder rather than through a library the reader configured;
     * a source the registry no longer holds was removed while its rows were still on the
     * shelf. Neither is a place the reader put above anything, so neither displaces a source
     * they did.
     */
    fun rank(sourceId: UUID?, sources: List<Source>): Int {
        if (sourceId == null) return Int.MAX_VALUE
        val index = sources.indexOfFirst { it.id == sourceId }
        return if (index < 0) Int.MAX_VALUE else index
    }

    /**
     * Whether a publication reached through [incoming] should displace the one already on the
     * shelf from [existing].
     *
     * Strictly higher, so a tie leaves the shelf alone. Two finds through the same source are
     * the same book twice — a second walk, a resumed scan — and rewriting the row for them
     * would make the answer depend on scan order again, which is the whole defect.
     */
    fun prefers(incoming: UUID?, over: UUID?, sources: List<Source>): Boolean =
        rank(incoming, sources) < rank(over, sources)
}
