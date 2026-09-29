package app.storyarc.core.smb

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network

/**
 * Watches the device's default network and drops every open SMB session on a change.
 *
 * `network-share`'s scenario *Network changes* asks a stale session to be dropped as soon as
 * the path underneath it moves, not only once a read against it has already failed and timed
 * out. [onAvailable] and [onLost] alone — not [ConnectivityManager.NetworkCallback
 * .onCapabilitiesChanged], which fires on a mere signal-strength wobble and would reopen a
 * session that was never actually gone.
 *
 * Started and stopped by the reader's own screen, for as long as it is on screen:
 * `SourceRetryTriggers` collects the same kind of signal for the library's sources and
 * deliberately stops while a reader is open, which is exactly why that collector cannot be
 * the one thing that reaches an *open* session's own handle.
 */
object SmbNetworkWatch {
    private var callback: ConnectivityManager.NetworkCallback? = null

    /** Starts watching, if nothing already is. Idempotent, so a screen may call it on every appearance. */
    @Synchronized
    fun start(context: Context) {
        if (callback != null) return
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return
        val watcher = object : ConnectivityManager.NetworkCallback() {
            private var current: Network? = null

            override fun onAvailable(network: Network) {
                val previous = current
                current = network
                if (isChange(previous, network)) SmbSourceRegistry.dropAll()
            }

            override fun onLost(network: Network) {
                if (current == network) current = null
                SmbSourceRegistry.dropAll()
            }
        }
        callback = watcher
        manager.registerDefaultNetworkCallback(watcher)
    }

    /** Stops watching. Safe to call whether or not [start] was. */
    @Synchronized
    fun stop(context: Context) {
        val watcher = callback ?: return
        callback = null
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return
        runCatching { manager.unregisterNetworkCallback(watcher) }
    }
}

/**
 * Whether a default network reported as available is a move to another one.
 *
 * A default-network callback reports the network already in effect the moment it is
 * registered. That report is not a change: reading it as one dropped every session the reader
 * had just opened, and the first read paid for a fresh one.
 */
internal fun <T : Any> isChange(previous: T?, next: T): Boolean = previous != null && previous != next
