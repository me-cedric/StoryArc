package app.storyarc.core.model

/**
 * When to ask a source again, and what its answer means.
 *
 * The two decisions in probing a source, separated from the asking. Reaching a server is
 * platform work and hard to test; deciding what a 401 means and how long to wait after the
 * fourth failure is neither, and is where the requirement actually lives. iOS's
 * `SourceProbe` is the same two functions, asserted against the same table.
 */
object SourceProbe {

    /** The first wait after a failure, and the longest one, in milliseconds. */
    const val FIRST_DELAY_MILLIS = 5_000L
    const val LONGEST_DELAY_MILLIS = 300_000L

    /**
     * How long to wait before asking again, after [failures] consecutive failures.
     *
     * Doubling from five seconds, and then not past five minutes. [failures] is a count, so
     * one failure means wait the first delay — a zero would mean "retry immediately", which
     * is the caller's business and not a backoff at all.
     *
     * The cap is what makes this safe to leave running: a source that has been off for a
     * day is asked every five minutes, not once every few hours, so a laptop coming back
     * onto the network is noticed while the reader is still holding the phone.
     */
    fun delayAfter(failures: Int): Long {
        if (failures <= 0) return 0
        // Shifting rather than a power: the exponent is small, and doubling 5 by hand keeps
        // the sequence readable — 5, 10, 20, 40, 80, 160, 300.
        val doublings = minOf(failures - 1, 16)
        val raw = FIRST_DELAY_MILLIS shl doublings
        return minOf(raw, LONGEST_DELAY_MILLIS)
    }

    /**
     * What an HTTP response says about a source.
     *
     * `sources` names four states and gives two of them to the server: a refused credential
     * is unauthorized, and anything else that is not a success is unreachable. The
     * distinction earns its place — one asks the reader to do something, the other must
     * not, because "offline is a normal state, not an error".
     *
     * 404 is deliberately unreachable rather than a fifth state. A catalogue that has moved
     * is, from the reader's side, a catalogue that is not answering; inventing a "gone"
     * state would put a red badge on something a reconnect might fix.
     */
    fun stateForStatus(code: Int, atEpochMillis: Long, reason: String): SourceConnectionState = when (code) {
        in 200..299 -> SourceConnectionState.Connected
        401, 403 -> SourceConnectionState.Unauthorized(reason)
        else -> SourceConnectionState.Unreachable(atEpochMillis)
    }

    /**
     * What a failure to reach the server at all says: the same as a bad status, because to
     * a reader a refused connection and a 500 are the same sentence.
     */
    fun stateForFailure(atEpochMillis: Long): SourceConnectionState =
        SourceConnectionState.Unreachable(atEpochMillis)

    /**
     * Whether a source is worth asking about over the network.
     *
     * A local folder is not: it is either readable or it is not, and that is a question for
     * the filesystem rather than one to back off from. `sources` scopes the whole
     * connection-state requirement to sources that can be unreachable.
     */
    fun isRemote(kind: SourceKind): Boolean = when (kind) {
        SourceKind.LOCAL_FOLDER -> false
        SourceKind.NETWORK_SHARE, SourceKind.OPDS_CATALOG, SourceKind.KAVITA_SERVER -> true
    }
}
