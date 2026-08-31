package app.storyarc.core.model

/**
 * Where someone stopped reading.
 *
 * A paged publication stores a page index. A reflowable one stores a fraction
 * through the content plus an opaque locator, because a reflowable page number
 * is a function of the reader's typography and is not stable across devices —
 * ADR-0006.
 */
sealed interface ReadingPosition {
    data class Page(val index: Int, val total: Int) : ReadingPosition
    data class Reflowable(val progression: Double, val locator: String) : ReadingPosition

    /** Normalised 0..1, so two positions compare regardless of kind. */
    val fraction: Double
        get() = when (this) {
            is Page -> if (total > 1) {
                (index.toDouble() / (total - 1).toDouble()).coerceIn(0.0, 1.0)
            } else {
                if (total == 1 && index >= 0) 1.0 else 0.0
            }
            is Reflowable -> progression.coerceIn(0.0, 1.0)
        }

    /**
     * Whether this describes the same point in a publication as another.
     *
     * By [fraction] rather than by case, because that is the currency the whole merge deals
     * in — and because a store is entitled to keep a synced position as the one number that
     * survives a change of typography. [app.storyarc.core.persistence.ProgressStore] does
     * exactly that, and while this was case equality a `Page` position could never equal the
     * one it had just been stored from, so ADR-0006's first row — remote ahead, local
     * untouched, adopt quietly — was unreachable. iOS's `matches(_:)` is the same line.
     */
    fun matches(other: ReadingPosition): Boolean = fraction == other.fraction
}

data class ReadingProgress(
    val identity: PublicationIdentity,
    val position: ReadingPosition,
    val isFinished: Boolean = false,
    /**
     * When it was finished, which `reading-progress` asks for by name: a publication is
     * "recorded finished with a completion timestamp".
     *
     * Separate from [updatedAtEpochMillis] because they answer different questions. That
     * one moves every fifteen seconds of reading; this moves once, and only when the
     * finished flag turns on. Reopening a finished publication writes a new position — and
     * must not rewrite when it was finished.
     */
    val finishedAtEpochMillis: Long? = null,
    val updatedAtEpochMillis: Long,
    /**
     * The last position successfully exchanged with the source. Comparing
     * against it is how the merge tells "changed since last sync" from
     * "untouched", which is the difference between a silent adopt and a notice.
     */
    val syncedPosition: ReadingPosition? = null,
) {
    /**
     * The record this one becomes when the finished flag is set or cleared.
     *
     * The timestamp is the point: it is stamped when the flag turns on, *kept* while it
     * stays on — so re-reading a finished publication does not restate when it was
     * finished — and dropped when it turns off, because an unfinished publication has no
     * completion to date. iOS's `finished(_:at:)` is the same three lines.
     */
    fun finished(finished: Boolean, atEpochMillis: Long): ReadingProgress = copy(
        isFinished = finished,
        finishedAtEpochMillis = if (finished) finishedAtEpochMillis ?: atEpochMillis else null,
        updatedAtEpochMillis = atEpochMillis,
    )
}

/** The outcome of merging a local record with a remote one. */
sealed interface ProgressMergeOutcome {
    /** Remote adopted with no user-visible notice. */
    data class AdoptRemote(val progress: ReadingProgress) : ProgressMergeOutcome

    /** Local kept; push it to the server. */
    data class KeepLocalAndPush(val progress: ReadingProgress) : ProgressMergeOutcome

    /**
     * Both moved since the last sync. The further position wins, and the user
     * is told once — naming both — with the option to take the other.
     */
    data class Conflict(
        val resolved: ReadingProgress,
        val discarded: ReadingPosition,
    ) : ProgressMergeOutcome
}

/**
 * ADR-0006's conflict rules, in one place, so both platforms can be checked
 * against the same table.
 *
 * | Situation | Result |
 * | --- | --- |
 * | Remote ahead, local untouched since last sync | adopt remote silently |
 * | Remote behind local | keep local, push |
 * | Both changed since last sync | further wins, tell the user once |
 * | One finished, one partial | finished wins |
 */
object ProgressMerge {
    fun merge(local: ReadingProgress, remote: ReadingProgress): ProgressMergeOutcome {
        // Finished is sticky. Unmarking a finished publication is a deliberate
        // act; losing it to a stale sync is never what someone wanted.
        if (remote.isFinished && !local.isFinished) {
            return ProgressMergeOutcome.AdoptRemote(remote)
        }
        if (local.isFinished && !remote.isFinished) {
            return ProgressMergeOutcome.KeepLocalAndPush(local)
        }

        val localMoved = local.syncedPosition?.let { !it.matches(local.position) } ?: true
        val remoteAhead = remote.position.fraction > local.position.fraction

        if (!localMoved) {
            // Nothing to lose locally: take whichever is further, quietly.
            return if (remoteAhead) {
                ProgressMergeOutcome.AdoptRemote(remote)
            } else {
                ProgressMergeOutcome.KeepLocalAndPush(local)
            }
        }

        val remoteMoved = local.syncedPosition?.let { !it.matches(remote.position) } ?: true
        if (!remoteMoved) {
            return ProgressMergeOutcome.KeepLocalAndPush(local)
        }

        // Genuine conflict. Furthest wins — clock skew between a phone and a NAS
        // is real, and being a few pages ahead is recoverable in a way that
        // losing an evening's reading is not.
        return when {
            remoteAhead -> ProgressMergeOutcome.Conflict(remote, local.position)
            local.position.fraction > remote.position.fraction ->
                ProgressMergeOutcome.Conflict(local, remote.position)
            // Identical positions are not a conflict at all.
            else -> ProgressMergeOutcome.KeepLocalAndPush(local)
        }
    }
}
