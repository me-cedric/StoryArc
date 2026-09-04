package app.storyarc.feature.library

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.util.concurrent.ConcurrentHashMap

/**
 * Whether the device has a network path, as a flow.
 *
 * **The observing half of [app.storyarc.core.model.SourceReachability], which owns the
 * deciding half.** That split is the point: `ConnectivityManager.NetworkCallback` needs a
 * real device and a real network, so a test that drove it would be a test nobody runs -- the
 * edge detection, the reading guard and the "something is away" condition all live in
 * `core/model` and take a signal as an argument. This is the one piece that cannot be tested
 * without a device, and it is deliberately the smallest piece: register a callback, report
 * whether anything is up, unregister on close.
 *
 * Separate from [NetworkCost], which asks the same manager a different question. Two
 * observers rather than one shared object because the questions have different lifetimes --
 * the cost is asked synchronously whenever a download is weighed, and this is collected for
 * as long as the library is on screen. iOS keeps `NetworkPaths` and `NetworkCost` apart for
 * the same reason.
 */
internal object NetworkPaths {

    /**
     * `true` while any network is up, reported on every change.
     *
     * The first report describes the network **as it already is** rather than a change to
     * it, which is why [app.storyarc.core.model.SourceReachability.triggers] assumes a path
     * before the flow opens: without that, launching with Wi-Fi on would read as a regain
     * and probe every configured source a moment after the library already did.
     *
     * **It is sent here rather than left to the callback**, and that is not a tidiness
     * choice. `registerDefaultNetworkCallback` says nothing at all when there is no default
     * network -- it only ever calls `onAvailable`. A collector that started offline would
     * therefore keep the assumed `true` until the network came back, read the regain as no
     * change, and never fire the one trigger the requirement is about. iOS gets the opening
     * report for free: `NWPathMonitor` reports an unsatisfied path as readily as a satisfied
     * one.
     *
     * A set rather than a single boolean, because the callbacks for a handover are not
     * ordered: swapping Wi-Fi for cellular can deliver the new network's `onAvailable`
     * before the old one's `onLost`, and a plain flag would then report a drop the device
     * never had -- which the edge detector would read as a regain on the next report.
     */
    fun satisfied(context: Context): Flow<Boolean> = callbackFlow {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        if (manager == null) {
            close()
            return@callbackFlow
        }

        // Touched from a binder thread, so a plain `MutableSet` would be a data race.
        val up = ConcurrentHashMap.newKeySet<Network>()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                up += network
                trySend(true)
            }

            override fun onLost(network: Network) {
                up -= network
                trySend(up.isNotEmpty())
            }
        }

        // The network as it already is, before any change to it. See the note above: the
        // callback is silent about an absent default network, so this is the only report
        // that can say the device started offline.
        manager.activeNetwork?.let { up += it }
        trySend(up.isNotEmpty())

        // The *default* network, which is the one a source is reached over. A request for
        // every network would report a regain for an interface nothing routes through.
        manager.registerDefaultNetworkCallback(callback)
        awaitClose { runCatching { manager.unregisterNetworkCallback(callback) } }
    }
}
