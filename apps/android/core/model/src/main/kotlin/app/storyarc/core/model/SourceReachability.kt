package app.storyarc.core.model

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Why the app would ask an away source again, unprompted.
 *
 * `sources`' *Retry policy* names two occasions beside the backoff: the app "retries
 * immediately, once, when the device regains network connectivity or the app returns to the
 * foreground". Two triggers, and they are deliberately one type rather than two call sites --
 * whether a trigger is allowed to probe is one decision ([SourceReachability.shouldProbe]),
 * and two call sites is how one of them ends up without the reading guard.
 *
 * iOS's `RetryTrigger` names the same two.
 */
enum class RetryTrigger {
    /** A network path appeared where there was none. */
    CONNECTIVITY_REGAINED,

    /** The app came back to the foreground. */
    RETURNED_TO_FOREGROUND,
}

/**
 * When a regained network or a returning app should ask a source again.
 *
 * The observer's *decisions*, separated from the observing, for the reason [SourceProbe]
 * separates the backoff from the asking: `ConnectivityManager.NetworkCallback` and
 * `NWPathMonitor` need a real device and a real network, and a test that needs either is a
 * test nobody runs. What is here takes a connectivity signal as an argument, so a test drives
 * it and the app hands it the platform's.
 *
 * iOS's `SourceReachability` is the same three functions, asserted against the same cases.
 */
object SourceReachability {

    /**
     * Whether this trigger should fire one immediate probe.
     *
     * Three conditions, and each of them is a sentence in `sources`.
     *
     * **Something has to be away.** The retry policy is scoped to a source that is
     * unreachable; a trigger arriving while everything is answering has nothing to reconnect,
     * and probing anyway would put a request per source on the network every time a reader
     * unlocks the phone.
     *
     * **A reader who is reading is left alone.** *Automatic recovery* reconnects "without
     * user action" and "does not present a notification or interrupt reading" -- so the clause
     * is a requirement about *not* doing something, and this is where it is kept. The backoff
     * loop is cancelled with the library on both platforms; a trigger is not, because it
     * arrives from the system rather than from a screen, and without this guard a dropped
     * Wi-Fi mid-chapter would probe every configured server while the reader is on a page.
     *
     * **Unauthorized is not unreachable.** A refused credential is the one state that asks
     * the reader to act, and no amount of network coming back makes a rejected key work --
     * retrying it would relist the same sheet on every hop.
     */
    fun shouldProbe(trigger: RetryTrigger, sources: List<Source>, isReading: Boolean): Boolean {
        // Both occasions pass the same gate, and taking the trigger is what makes that
        // visible at the call site. A `when` rather than an ignored parameter, for the reason
        // `SourceKind.isBrowsable` matches rather than comparing: a third occasion has to be
        // answered here instead of quietly inheriting whatever these two do.
        when (trigger) {
            RetryTrigger.CONNECTIVITY_REGAINED, RetryTrigger.RETURNED_TO_FOREGROUND -> Unit
        }
        if (isReading) return false
        return sources.any { it.state is SourceConnectionState.Unreachable }
    }

    /**
     * What a report from a connectivity monitor is worth, given the last one.
     *
     * Only a *transition* to having a path is a regained connection. A monitor reports every
     * path change -- one Wi-Fi network swapped for another, an interface coming up beside the
     * one already carrying traffic, a VPN attaching -- and reading each of those as a regain
     * would turn "retries immediately, once" into a probe per hop. Losing the path is no
     * trigger at all: there is nothing to reach.
     *
     * Returns null when nothing worth acting on happened, which is most reports.
     */
    fun triggerFor(hasNetwork: Boolean, previously: Boolean): RetryTrigger? =
        if (hasNetwork && !previously) RetryTrigger.CONNECTIVITY_REGAINED else null

    /**
     * The triggers an injected connectivity signal produces.
     *
     * The signal is a parameter rather than a callback registered here: that is what keeps
     * the edge detection above testable without a device, and it is the same reason
     * `LibraryScanner` takes its reconcile question as a lambda.
     *
     * @param startingFrom whether the device is assumed to have a path before the first
     *   report arrives. `true`, so a callback's opening report -- which describes the network
     *   as it already is rather than a change to it -- is not read as a regain and does not
     *   probe every source a moment after the library already did.
     */
    fun triggers(paths: Flow<Boolean>, startingFrom: Boolean = true): Flow<RetryTrigger> = flow {
        var had = startingFrom
        paths.collect { hasNetwork ->
            triggerFor(hasNetwork, had)?.let { emit(it) }
            had = hasNetwork
        }
    }
}
