package app.storyarc.core.model

/**
 * What a pull did, so a caller can write it down and say what needs telling.
 *
 * `reading-progress`: "progress recorded on other devices is merged into the local store",
 * and a genuine conflict is one the user "is told once -- naming both -- with the option to
 * take the other". Those are two different results and a caller has to act differently on
 * each, so a pull reports them apart rather than returning a list of records.
 *
 * iOS's `ProgressPull` merges the same way.
 */
data class ProgressPull(
    /** Records to write, whether they came from the server or were kept locally. */
    val toSave: List<ReadingProgress> = emptyList(),
    /**
     * Records the server does not have, or has behind. `reading-progress` requires a failed
     * push to be "queued and retried on the next successful connection".
     */
    val toPush: List<ReadingProgress> = emptyList(),
    /** The conflicts worth a sentence, with what was set aside so it can be offered back. */
    val conflicts: List<Conflict> = emptyList(),
) {
    data class Conflict(val resolved: ReadingProgress, val discarded: ReadingPosition)

    companion object {
        /**
         * Merges what a source reports against what is held locally.
         *
         * The rules themselves are [ProgressMerge]'s, and were written, tested and
         * unreachable until this: nothing called them, so `reading-progress`'s whole
         * synchronisation requirement rested on a table nobody consulted. This is the caller.
         *
         * Pure, and takes both sides as values rather than reaching for a store, so the same
         * table can be asserted on both platforms without a server or a device.
         *
         * A publication the server has and the reader has never opened is adopted outright:
         * there is nothing local to weigh it against, and refusing it would mean a reader who
         * read a chapter on another device opens this one at page one.
         */
        fun merging(
            remote: List<ReadingProgress>,
            local: (PublicationIdentity) -> ReadingProgress?,
        ): ProgressPull {
            val toSave = mutableListOf<ReadingProgress>()
            val toPush = mutableListOf<ReadingProgress>()
            val conflicts = mutableListOf<Conflict>()

            for (record in remote) {
                val held = local(record.identity)
                if (held == null) {
                    toSave += record
                    continue
                }
                when (val outcome = ProgressMerge.merge(local = held, remote = record)) {
                    is ProgressMergeOutcome.AdoptRemote -> toSave += outcome.progress
                    is ProgressMergeOutcome.KeepLocalAndPush -> toPush += outcome.progress
                    is ProgressMergeOutcome.Conflict -> {
                        toSave += outcome.resolved
                        // A conflict the local position won leaves the server behind exactly
                        // as the plain case above does, and `reading-progress` says a server
                        // that is behind is pushed to. Left out, the next refresh finds the
                        // same disagreement and raises the same notice -- and the requirement
                        // is that the reader is told once.
                        if (outcome.resolved.position.matches(held.position)) {
                            toPush += outcome.resolved
                        }
                        conflicts += Conflict(outcome.resolved, outcome.discarded)
                    }
                }
            }

            return ProgressPull(toSave, toPush, conflicts)
        }
    }
}
