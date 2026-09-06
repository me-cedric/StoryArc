package app.storyarc.feature.library

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/**
 * What the connection costs, and what it is made of.
 *
 * `network-share` asks [isCareful] before streaming: on such a connection the reader confirms
 * first. `offline-downloads` asks it to lower the bound, and asks [onWifi] the other question
 * -- "download over Wi-Fi only" is about the medium rather than about the cost.
 *
 * Separate from [NetworkPaths], which asks the same manager whether *any* network is up. Two
 * observers rather than one shared object because the questions have different lifetimes and
 * different answers; iOS keeps `NetworkCost` and `NetworkPaths` apart for the same reason.
 */
object NetworkCost {
    fun isCareful(context: Context): Boolean {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return true
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return true
        val unmetered = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        val saverOff = manager.restrictBackgroundStatus ==
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED
        return !(unmetered && saverOff)
    }

    /** Whether the default network is Wi-Fi or Ethernet, asked once. */
    fun isOnWifi(context: Context): Boolean =
        isOnWifi(context.getSystemService(ConnectivityManager::class.java))

    private fun isOnWifi(manager: ConnectivityManager?): Boolean {
        val capabilities = manager?.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return carriesWifi(capabilities)
    }

    private fun carriesWifi(capabilities: NetworkCapabilities): Boolean =
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)

    /**
     * Whether the device is on Wi-Fi, now and after every change to the default network.
     *
     * `registerDefaultNetworkCallback` is the platform's own answer to "tell me when this
     * changes", and [DownloadQueue] collects it so a queue paused for Wi-Fi starts again
     * without the reader going back to the screen.
     *
     * **[ConnectivityManager.NetworkCallback.onCapabilitiesChanged] rather than
     * `onAvailable`.** Both fire when an interface comes up, and the capabilities are what
     * carry the transport this asks about. A network that stays but changes -- Wi-Fi that
     * starts reporting itself as metered -- reports only through the capabilities.
     *
     * **The opening report is sent here rather than left to the callback**, for the reason
     * [NetworkPaths] gives: the callback says nothing at all while there is no default
     * network, so a collector that started offline would never hear the first answer.
     *
     * The callback is unregistered when collection ends. [DownloadQueue.close] ends it.
     */
    fun onWifi(context: Context): Flow<Boolean> = callbackFlow {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        if (manager == null) {
            trySend(false)
            close()
            return@callbackFlow
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                trySend(carriesWifi(capabilities))
            }

            override fun onLost(network: Network) {
                trySend(isOnWifi(manager))
            }
        }

        trySend(isOnWifi(manager))
        manager.registerDefaultNetworkCallback(callback)
        awaitClose { runCatching { manager.unregisterNetworkCallback(callback) } }
    }
}
