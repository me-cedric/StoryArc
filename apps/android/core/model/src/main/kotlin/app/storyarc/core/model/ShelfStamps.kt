package app.storyarc.core.model

import java.util.UUID

/** Shelves with the deletions that go with them. */
data class StampedShelves(val shelves: Shelves, val removed: List<ShelfTombstone>)

/**
 * When each shelf changed, which shelves were deleted, and how two devices' shelves merge.
 *
 * `library-sync` tasks 3.3 and 3.4. iOS's `ShelfStamps` applies the same rules.
 */
object ShelfStamps {

    /**
     * The shelves a store writes, with each change the reader made stamped and each deletion
     * recorded.
     *
     * A shelf whose content changed while its moment did not is stamped [now]; a moment the
     * caller changed came from a merge and stays. A local shelf that is gone, with no tombstone
     * for it, gets one. A shelf that comes back where a tombstone stands is stamped [now] and
     * the tombstone goes: the reader put it back.
     */
    fun stamped(
        before: Shelves,
        beforeRemoved: List<ShelfTombstone>,
        after: Shelves,
        afterRemoved: List<ShelfTombstone>,
        now: Long,
    ): StampedShelves {
        val removedIds = afterRemoved.map { it.id }.toSet()
        val priorCollections = before.collections.associateBy { it.id }
        val priorLists = before.lists.associateBy { it.id }
        val collections = after.collections.map { shelf ->
            val prior = priorCollections[shelf.id]
            val fresh = shelf.origin == ShelfOrigin.Local && changed(
                shelf.id in removedIds, shelf.changedAtEpochMillis, prior?.changedAtEpochMillis,
                prior != null && shelf.copy(changedAtEpochMillis = prior.changedAtEpochMillis) != prior,
            )
            if (fresh) shelf.copy(changedAtEpochMillis = now) else shelf
        }
        val lists = after.lists.map { shelf ->
            val prior = priorLists[shelf.id]
            val fresh = shelf.origin == ShelfOrigin.Local && changed(
                shelf.id in removedIds, shelf.changedAtEpochMillis, prior?.changedAtEpochMillis,
                prior != null && shelf.copy(changedAtEpochMillis = prior.changedAtEpochMillis) != prior,
            )
            if (fresh) shelf.copy(changedAtEpochMillis = now) else shelf
        }
        val present = localIds(after)
        val gone = (localIds(before) - present - removedIds).map { ShelfTombstone(it, now) }
        val known = afterRemoved.filter { it.id !in present }
        // A tombstone this store held and the caller did not hand back still stands.
        val kept = beforeRemoved.filter { old -> old.id !in present && known.none { it.id == old.id } }
        return StampedShelves(Shelves(collections, lists), known + kept + gone)
    }

    private fun changed(tombstoned: Boolean, moment: Long, priorMoment: Long?, differs: Boolean): Boolean =
        when (priorMoment) {
            null -> tombstoned || moment == 0L
            else -> differs && moment == priorMoment
        }

    private fun localIds(shelves: Shelves): Set<UUID> =
        shelves.collections.filter { it.origin == ShelfOrigin.Local }.map { it.id }.toSet() +
            shelves.lists.filter { it.origin == ShelfOrigin.Local }.map { it.id }.toSet()

    /**
     * This device's shelves merged with the document's.
     *
     * Members are a union, so a member added on either device survives. The name and the cover
     * come from the side that changed last. A reading list keeps the older side's order first
     * and puts the other side's new entries after it. A tombstone wins over a shelf whose last
     * change is not newer than the deletion; a shelf changed after it comes back.
     */
    fun merging(local: Shelves, localRemoved: List<ShelfTombstone>, document: LibraryBody): StampedShelves {
        val removed = (localRemoved + document.removedShelves.mapNotNull(::tombstone))
            .groupBy { it.id }
            .mapValues { (_, all) -> all.maxBy { it.removedAtEpochMillis } }
            .toMutableMap()

        fun <S> settle(id: UUID, shelf: S?, moment: (S) -> Long): S? {
            shelf ?: return null
            val tombstone = removed[id] ?: return shelf
            if (ChangeStamps.seconds(moment(shelf)) <= ChangeStamps.seconds(tombstone.removedAtEpochMillis)) {
                return null
            }
            removed.remove(id)
            return shelf
        }

        val mineCollections = local.collections.filter { it.origin == ShelfOrigin.Local }.associateBy { it.id }
        val theirCollections = document.collections.mapNotNull(::collection).associateBy { it.id }
        val collections = (mineCollections.keys + theirCollections.keys).mapNotNull { id ->
            val mine = mineCollections[id]
            val theirs = theirCollections[id]
            val shelf = if (mine != null && theirs != null) union(mine, theirs) else mine ?: theirs
            settle(id, shelf) { it.changedAtEpochMillis }
        }

        val mineLists = local.lists.filter { it.origin == ShelfOrigin.Local }.associateBy { it.id }
        val theirLists = document.readingLists.mapNotNull(::list).associateBy { it.id }
        val lists = (mineLists.keys + theirLists.keys).mapNotNull { id ->
            val mine = mineLists[id]
            val theirs = theirLists[id]
            val shelf = if (mine != null && theirs != null) union(mine, theirs) else mine ?: theirs
            settle(id, shelf) { it.changedAtEpochMillis }
        }

        val shelves = Shelves(
            collections = local.collections.filter { it.origin != ShelfOrigin.Local } + collections,
            lists = local.lists.filter { it.origin != ShelfOrigin.Local } + lists,
        )
        return StampedShelves(shelves, removed.values.sortedBy { it.id })
    }

    private fun newer(mine: Long, theirs: Long): Boolean =
        ChangeStamps.seconds(theirs) > ChangeStamps.seconds(mine)

    private fun union(mine: PublicationCollection, theirs: PublicationCollection): PublicationCollection {
        val last = if (newer(mine.changedAtEpochMillis, theirs.changedAtEpochMillis)) theirs else mine
        return last.copy(
            members = mine.members + theirs.members,
            changedAtEpochMillis = maxOf(mine.changedAtEpochMillis, theirs.changedAtEpochMillis),
        )
    }

    private fun union(mine: ReadingList, theirs: ReadingList): ReadingList {
        val last = if (newer(mine.changedAtEpochMillis, theirs.changedAtEpochMillis)) theirs else mine
        // The older side's order first. On the same second this device's order goes first, as
        // an import keeps it.
        val mineFirst = !newer(theirs.changedAtEpochMillis, mine.changedAtEpochMillis)
        val (first, second) = if (mineFirst) mine to theirs else theirs to mine
        return last.copy(
            entries = first.entries + second.entries.filterNot { it in first.entries },
            changedAtEpochMillis = maxOf(mine.changedAtEpochMillis, theirs.changedAtEpochMillis),
        )
    }

    private fun collection(arriving: DocumentCollection): PublicationCollection? =
        LibraryImport.wireId(arriving.id)?.let { id ->
            PublicationCollection(
                id = id,
                name = arriving.name,
                members = arriving.members.toSet(),
                coverMemberId = arriving.coverMemberId,
                changedAtEpochMillis = epochMillis(arriving.changedAt) ?: 0L,
            )
        }

    private fun list(arriving: DocumentReadingList): ReadingList? =
        LibraryImport.wireId(arriving.id)?.let { id ->
            ReadingList(
                id = id,
                name = arriving.name,
                entries = arriving.entries,
                coverMemberId = arriving.coverMemberId,
                changedAtEpochMillis = epochMillis(arriving.changedAt) ?: 0L,
            )
        }

    private fun tombstone(arriving: DocumentTombstone): ShelfTombstone? {
        val id = LibraryImport.wireId(arriving.id) ?: return null
        val at = epochMillis(arriving.removedAt) ?: return null
        return ShelfTombstone(id, at)
    }
}
