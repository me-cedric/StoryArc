package app.storyarc.feature.library

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/**
 * Whether the connection is one to be careful with.
 *
 * `offline-downloads`: the bound is "lowered on a metered connection", and "when the
 * platform's data saver or Low Data Mode is active ... the app treats the connection as
 * metered regardless of its own setting". `network-share` asks the same question before
 * streaming: on such a connection the reader confirms first.
 *
 * Careful by default, so an unknown connection is treated as the expensive one.
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
}
