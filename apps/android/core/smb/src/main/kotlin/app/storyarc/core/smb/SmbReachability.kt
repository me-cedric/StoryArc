package app.storyarc.core.smb

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Whether reads from shares are getting through.
 *
 * `network-share` asks for an indicator "only if a page is actually blocked on the network
 * for more than 2 seconds", and for an offer to download after 60 seconds of failure. Both
 * are questions about time, so what is published is *when* trouble started rather than a
 * boolean -- a screen can then decide its own thresholds without this having to know them.
 *
 * One object for the whole app rather than one per source: a reader turning pages holds one
 * archive, and two indicators for one dropped Wi-Fi would be one too many.
 */
object SmbReachability {
    private val _blockedSince = MutableStateFlow<Long?>(null)

    /** When reads started failing, or null while they are getting through. */
    val blockedSince: StateFlow<Long?> = _blockedSince.asStateFlow()

    /** A read failed. The first failure is the one whose time is kept. */
    fun noteFailure(now: Long) {
        _blockedSince.compareAndSet(null, now)
    }

    /** A read got through. Whatever was wrong is over. */
    fun noteSuccess() {
        _blockedSince.value = null
    }

    /** Forgets the current trouble, for a reader who dismissed the notice. */
    fun clear() {
        _blockedSince.value = null
    }
}
