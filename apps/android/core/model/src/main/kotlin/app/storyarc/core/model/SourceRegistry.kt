package app.storyarc.core.model

import java.util.UUID

/**
 * The ordered list of configured sources, and every change that can be made to it.
 *
 * `sources` requires "an ordered, persistent registry". Order is not decoration: the same
 * requirement says the combined library "lists titles from higher sources first when two
 * sources hold the same publication", so position carries meaning and a `Set` would lose
 * it.
 *
 * A value type with pure operations, like [ShelfMemory]. Every change returns a new
 * registry, which is what lets a store save the result of an edit rather than reasoning
 * about how the edit happened. iOS's `SourceRegistry` holds the same table.
 */
data class SourceRegistry(
    /** In the order a reader put them, which is the order the library reads them. */
    val sources: List<Source> = emptyList(),
    /** Sources removed and not yet forgotten. See [removing]. */
    val tombstones: List<SourceTombstone> = emptyList(),
) {
    operator fun get(id: UUID): Source? = sources.firstOrNull { it.id == id }

    /**
     * Adds a source at the end.
     *
     * At the end rather than the front: the order is the reader's, and a new source
     * pushing itself above the ones they arranged would undo that arrangement.
     */
    fun adding(source: Source): SourceRegistry =
        if (this[source.id] != null) this else copy(sources = sources + source)

    /**
     * Renames a source.
     *
     * A blank name is refused rather than stored. `sources` requires the name to appear
     * "everywhere the source is referenced, including download attributions and error
     * messages", and a blank one would make those sentences read as if a word were
     * missing.
     */
    fun renaming(id: UUID, name: String): SourceRegistry {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return this
        return copy(sources = sources.map { if (it.id == id) it.copy(displayName = trimmed) else it })
    }

    /**
     * Moves a source to a new position.
     *
     * Takes the destination a drag reports, which is an index in the list *before* the
     * move. Removing first and inserting after would land one place early for every
     * downward drag.
     */
    fun moving(id: UUID, destination: Int): SourceRegistry {
        val from = sources.indexOfFirst { it.id == id }
        if (from < 0) return this
        val moved = sources.toMutableList()
        val source = moved.removeAt(from)
        val to = (if (destination > from) destination - 1 else destination).coerceIn(0, moved.size)
        moved.add(to, source)
        return copy(sources = moved)
    }

    /**
     * Removes a source, and remembers that it was removed.
     *
     * The tombstone is the whole point. `sources` requires the app to retain "local
     * reading progress for those publications for 30 days, so re-adding the same source
     * restores where the user stopped". So removal must *not* cascade to the progress
     * store, and something has to know when it is safe to.
     *
     * Re-adding a source with the same identifier clears its tombstone, which is what
     * makes the retention promise true rather than merely delayed.
     */
    fun removing(id: UUID, atEpochMillis: Long): SourceRegistry {
        if (this[id] == null) return this
        return copy(
            sources = sources.filterNot { it.id == id },
            tombstones = tombstones.filterNot { it.sourceId == id } +
                SourceTombstone(id, atEpochMillis),
        )
    }

    /**
     * The sources whose progress may now be forgotten, and a registry without them.
     *
     * Separated from [removing] on purpose: deciding *when* the 30 days are up is a
     * different question from deciding that a source is gone, and the caller that deletes
     * reading positions should be the one that asks. Losing a reading position is the one
     * thing ADR-0006 says the app must never do by accident.
     */
    fun collectingExpiredTombstones(
        atEpochMillis: Long,
        retentionMillis: Long = SourceTombstone.RETENTION_MILLIS,
    ): Pair<SourceRegistry, List<UUID>> {
        val expired = tombstones.filter { atEpochMillis - it.removedAtEpochMillis >= retentionMillis }
        if (expired.isEmpty()) return this to emptyList()
        val expiredIds = expired.map { it.sourceId }.toSet()
        return copy(tombstones = tombstones.filterNot { it.sourceId in expiredIds }) to
            expired.map { it.sourceId }
    }

    /**
     * Re-adding a source the reader removed, with its progress intact.
     *
     * The tombstone goes, so the collection pass stops considering it.
     */
    fun readding(source: Source): SourceRegistry = copy(
        sources = sources + source,
        tombstones = tombstones.filterNot { it.sourceId == source.id },
    )
}

/**
 * A source that was removed, and when.
 *
 * Kept so the progress belonging to its publications can outlive it for a while. See
 * [SourceRegistry.removing].
 */
data class SourceTombstone(val sourceId: UUID, val removedAtEpochMillis: Long) {
    companion object {
        /**
         * Thirty days, from `sources`. Long enough that a reader who removed a server by
         * mistake and noticed a week later loses nothing.
         */
        const val RETENTION_MILLIS = 30L * 24 * 60 * 60 * 1000
    }
}
