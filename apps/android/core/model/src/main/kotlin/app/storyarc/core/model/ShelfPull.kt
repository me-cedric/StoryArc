package app.storyarc.core.model

/** The outcome of reconciling one server-backed shelf with the edits waiting for it. */
sealed interface ShelfMergeOutcome {
    /** The server is where it was left. Send these, and say nothing. */
    data class Push(val edits: List<ShelfEdit>) : ShelfMergeOutcome

    /**
     * The server already holds every edit that was waiting. Forget them, and say nothing --
     * an edit that arrived is not a change worth a sentence.
     */
    data class Settled(val edits: List<ShelfEdit>) : ShelfMergeOutcome

    /**
     * The server moved under a pending edit. Its version wins: [discarded] is what the
     * reader loses and has to be told about, [settled] arrived before the change and is
     * simply forgotten.
     */
    data class Conflict(
        val discarded: List<ShelfEdit>,
        val settled: List<ShelfEdit>,
    ) : ShelfMergeOutcome
}

/**
 * `collections-and-reading-lists`' two offline rules, in one place, so both platforms can be
 * checked against the same table.
 *
 * | Situation | Result |
 * | --- | --- |
 * | Nothing waiting | settle nothing, say nothing |
 * | The server already holds everything that was waiting | settled, silently |
 * | The server holds what it held when the edit was made | push what is outstanding |
 * | The server moved under an outstanding edit | server wins, edit discarded, tell once |
 * | This shelf has never answered this device | push -- losing the edit is what offline must never do |
 *
 * The last row is the one that looks like a compromise and is not. Without a baseline "did
 * the server change" is unanswerable, and the two ways of guessing are not symmetrical:
 * pushing an addition the server already has changes nothing, while discarding it loses work
 * the reader can see they did.
 *
 * iOS's `ShelfMerge` decides the same five rows in the same order.
 */
object ShelfMerge {

    fun merge(
        baseline: List<String>?,
        remote: List<String>,
        pending: List<ShelfEdit>,
    ): ShelfMergeOutcome {
        val held = remote.toSet()
        val landed = pending.filter { it.entry in held }
        val waiting = pending.filterNot { it.entry in held }

        // Nothing outstanding: whatever was queued, the server has it now. Covers an empty
        // queue, which is the ordinary case and must not raise a notice.
        if (waiting.isEmpty()) return ShelfMergeOutcome.Settled(landed)

        if (baseline == null) return ShelfMergeOutcome.Push(waiting)

        // Take our own arrivals back out before comparing. A list that differs from the
        // baseline only by an edit this device made is a list nobody else has touched.
        val ours = landed.map { it.entry }.toSet()
        val withoutOurs = remote.filterNot { it in ours }
        if (withoutOurs == baseline) return ShelfMergeOutcome.Push(waiting)

        return ShelfMergeOutcome.Conflict(discarded = waiting, settled = landed)
    }

    /**
     * What a reading list looks like while edits are still waiting for the server.
     *
     * The server's own entries first, in the server's order -- it owns the order -- and the
     * outstanding ones after, oldest first, each marked. `collections-and-reading-lists`
     * wants the edit "applied locally" *and* the pending state "visible on the list", and
     * this is both at once: the entry is there, and it is visibly not there yet.
     */
    fun projecting(remote: List<ShelfEntry>, pending: List<ShelfEdit>): List<ShelfEntry> {
        val held = remote.map { it.id }.toSet()
        return remote + pending
            .filterNot { it.entry in held }
            .sortedBy { it.madeAt }
            .map { ShelfEntry(id = it.entry, title = it.title, isPending = true) }
    }
}

/**
 * What one round of reconciling every server-backed shelf produced.
 *
 * The same shape [ProgressPull] has, and for the same reason: a caller has to act
 * differently on each of the three, so they come back apart rather than as one list.
 *
 * iOS's `ShelfPull` merges the same way.
 */
data class ShelfPull(
    /** Edits to send now. The server is where it was left. */
    val toPush: List<ShelfEdit> = emptyList(),
    /** Edits nothing more is owed for -- delivered, or discarded by a conflict. */
    val toDrop: List<ShelfEdit> = emptyList(),
    /** The conflicts worth a sentence, one per shelf, naming what was set aside. */
    val conflicts: List<Conflict> = emptyList(),
) {
    data class Conflict(val shelf: ShelfKey, val discarded: List<ShelfEdit>)

    companion object {
        /**
         * Runs [ShelfMerge] across every shelf that answered this round.
         *
         * Pure, and takes both sides as values rather than reaching for a store, so the same
         * table can be asserted on both platforms without a server or a device.
         *
         * A shelf that did not answer is absent from [remote] and is left entirely alone:
         * its edits stay queued, its baseline stays as it was, and nobody is told anything.
         * That is the unreachable server, and it is not a conflict.
         */
        fun merging(
            remote: List<ShelfSnapshot>,
            baseline: (ShelfKey) -> List<String>?,
            pending: List<ShelfEdit>,
        ): ShelfPull {
            val toPush = mutableListOf<ShelfEdit>()
            val toDrop = mutableListOf<ShelfEdit>()
            val conflicts = mutableListOf<Conflict>()

            for (snapshot in remote) {
                val waiting = pending.filter { it.shelf == snapshot.shelf }.sortedBy { it.madeAt }
                when (
                    val outcome = ShelfMerge.merge(
                        baseline = baseline(snapshot.shelf),
                        remote = snapshot.entries,
                        pending = waiting,
                    )
                ) {
                    is ShelfMergeOutcome.Push -> toPush += outcome.edits
                    is ShelfMergeOutcome.Settled -> toDrop += outcome.edits
                    is ShelfMergeOutcome.Conflict -> {
                        toDrop += outcome.settled + outcome.discarded
                        conflicts += Conflict(snapshot.shelf, outcome.discarded)
                    }
                }
            }

            return ShelfPull(toPush, toDrop, conflicts)
        }
    }
}
