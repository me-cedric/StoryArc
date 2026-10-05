package app.storyarc.core.smb

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

data class SmbHost(val name: String, val address: String, val port: Int)

/**
 * The hosts one discovery has resolved, in the order they answered.
 *
 * Its own class, and synchronised, because `NsdManager` calls back on threads of its own: a
 * host that resolves while another is being removed would otherwise read the map mid-write,
 * and a [LinkedHashMap] answers that with a `ConcurrentModificationException`. The order is
 * the answering order rather than a sort, so a list already on screen does not reshuffle
 * under the reader's finger when a later host joins it.
 */
internal class FoundHosts {
    private val byName = LinkedHashMap<String, SmbHost>()

    /** Records [name] at [address], replacing an earlier answer from the same name. */
    fun resolved(name: String, address: String, port: Int): List<SmbHost> = synchronized(byName) {
        byName[name] = SmbHost(name, address, port)
        byName.values.toList()
    }

    /** Drops [name]. A name this discovery never resolved is not an error: it is simply absent. */
    fun lost(name: String): List<SmbHost> = synchronized(byName) {
        byName.remove(name)
        byName.values.toList()
    }
}

object SmbDiscovery {
    private const val SERVICE_TYPE = "_smb._tcp."

    fun hosts(context: Context): Flow<List<SmbHost>> = callbackFlow {
        val manager = context.getSystemService(NsdManager::class.java)
        if (manager == null) {
            send(emptyList())
            close()
            return@callbackFlow
        }

        val found = FoundHosts()

        // A new one for every resolve, never a shared instance. `NsdManager` holds a resolve
        // listener in a map keyed by the instance itself and removes it only when that one
        // resolve succeeds or fails, so a second resolve handed the same listener throws
        // `IllegalArgumentException("listener already in use")` -- on `NsdManager`'s own
        // callback thread, where nothing catches it, so the app goes down rather than the
        // resolve failing. Two shares on a network answer in the same breath, which is why
        // the crash needed a second host to show itself and why one share never saw it.
        fun resolver(): NsdManager.ResolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) = Unit

            override fun onServiceResolved(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                val address = info.host?.hostAddress ?: return
                trySend(found.resolved(info.serviceName, address, info.port))
            }
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, code: Int) { close() }
            override fun onStopDiscoveryFailed(type: String, code: Int) = Unit

            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                manager.resolveService(info, resolver())
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                trySend(found.lost(info.serviceName))
            }
        }

        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        awaitClose { runCatching { manager.stopServiceDiscovery(listener) } }
    }
}
