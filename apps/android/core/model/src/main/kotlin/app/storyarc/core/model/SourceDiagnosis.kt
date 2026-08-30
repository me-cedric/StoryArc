package app.storyarc.core.model

/**
 * What a source's detail screen says, and what it offers to do about it.
 *
 * `sources` names five fields — "the state, the last successful sync, the last error in
 * plain language, the item count, and the bytes downloaded" — and five actions: test the
 * connection, refresh, clear the cache, remove downloads, remove the source. The settings
 * list carried two of the fields and one of the actions, so this is the answer to the
 * scenario rather than a tidier arrangement of what was already there.
 *
 * A value computed from a source and the downloads it produced, not a screen. Which actions
 * a particular source can be offered is a decision with three inputs and no pixels, and it
 * was exactly the kind of decision the audit found untestable because it lived in a view.
 * iOS's `SourceDiagnosis` answers the same five the same way.
 */
data class SourceDiagnosis(
    val state: SourceConnectionState,
    val lastSuccessfulSyncEpochMillis: Long?,
    /**
     * The last error, or null when the source is not in one.
     *
     * Derived from the state rather than remembered beside it. A source that failed an hour
     * ago and is answering now has no error a reader needs to read, and a field that kept
     * one would be reporting the past as though it were the present — the same argument
     * that keeps connection state off disk.
     */
    val failure: SourceFailure?,
    /** How many publications the library holds from this source. */
    val itemCount: Int,
    /**
     * How many of them are downloaded, and what they weigh.
     *
     * Counted from the finished downloads alone: a queued one has no bytes on disk to free,
     * so counting it would make "remove downloads" offer to free nothing.
     */
    val downloadCount: Int,
    val downloadedBytes: Long,
    /** In the order the screen shows them, destructive last. */
    val actions: List<SourceAction>,
) {
    companion object {
        /**
         * Everything the detail screen needs about one source.
         *
         * [isRemovable] is the caller's because the one source that cannot be removed is not
         * a source the reader added — "On this device" is the app's own imported copies, and
         * `local-library` deletes those one at a time, naming each.
         */
        fun of(
            source: Source,
            itemCount: Int,
            downloads: List<Download>,
            isRemovable: Boolean = true,
        ): SourceDiagnosis {
            val mine = downloads.filter { it.sourceId == source.id && it.state.isFinished }
            val actions = buildList {
                add(SourceAction.TEST_CONNECTION)
                add(SourceAction.REFRESH)
                add(SourceAction.CLEAR_CACHE)
                // Only when there is something to remove. An action that frees nothing still
                // asks for a confirmation, and a reader who answers it watches nothing
                // happen.
                if (mine.isNotEmpty()) add(SourceAction.REMOVE_DOWNLOADS)
                if (isRemovable) add(SourceAction.REMOVE)
            }

            return SourceDiagnosis(
                state = source.state,
                lastSuccessfulSyncEpochMillis = source.lastSuccessfulSyncEpochMillis,
                failure = SourceFailure.of(source.state),
                itemCount = itemCount,
                downloadCount = mine.size,
                downloadedBytes = mine.sumOf { it.downloadedBytes },
                actions = actions,
            )
        }
    }
}

/**
 * Why a source is not answering, in the two ways it can fail.
 *
 * The wording is presentation and lives in the feature that draws it; this is which sentence
 * to draw and what to put in it. Splitting the two is what lets the decision be asserted
 * without a resource table.
 */
sealed interface SourceFailure {
    data class Unreachable(val sinceEpochMillis: Long) : SourceFailure
    data class Unauthorized(val reason: String) : SourceFailure

    companion object {
        /**
         * Null for a source that is connected or still connecting: neither is an error, and
         * `sources` is explicit that offline "is a normal state, not an error".
         */
        fun of(state: SourceConnectionState): SourceFailure? = when (state) {
            is SourceConnectionState.Connected, is SourceConnectionState.Connecting -> null
            is SourceConnectionState.Unreachable -> Unreachable(state.sinceEpochMillis)
            is SourceConnectionState.Unauthorized -> Unauthorized(state.reason)
        }
    }
}

/** What a source's detail screen can do to it. */
enum class SourceAction {
    /** Ask the source, now. For a folder that is whether it can still be read. */
    TEST_CONNECTION,

    /** Re-fetch the catalogue. */
    REFRESH,

    /** Drop the cached catalogue and covers. The downloads stay. */
    CLEAR_CACHE,

    /** Delete the files this source produced. The source stays. */
    REMOVE_DOWNLOADS,

    /** Remove the source, its cache, its secret and its downloads. */
    REMOVE,
    ;

    /**
     * Whether the action needs a confirmation before it happens.
     *
     * Clearing a cache does not: it costs a refresh and nothing else. The other two delete
     * bytes a reader may be relying on being there on a train.
     */
    val isDestructive: Boolean
        get() = when (this) {
            TEST_CONNECTION, REFRESH, CLEAR_CACHE -> false
            REMOVE_DOWNLOADS, REMOVE -> true
        }
}
