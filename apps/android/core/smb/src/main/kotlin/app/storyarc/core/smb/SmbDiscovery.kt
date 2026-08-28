package app.storyarc.core.smb

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

/** A host advertising SMB on the local network. */
data class SmbHost(val name: String, val address: String, val port: Int)

/**
 * Hosts advertising SMB on the local network.
 *
 * `network-share` marks discovery a SHOULD, and is firm about what it must not become:
 * "manual entry is always available and never gated behind discovery". So this is a list
 * that grows beside the form, and an empty one costs a reader nothing.
 *
 * mDNS, because that is what a NAS actually advertises -- `_smb._tcp` is registered by
 * Samba, by macOS file sharing, and by every consumer NAS this app is likely to meet.
 */
object SmbDiscovery {
    private const val SERVICE_TYPE = "_smb._tcp."

    /**
     * Emits the set of hosts seen so far, growing as replies arrive.
     *
     * The whole set each time rather than one host at a time: a screen wants to draw a
     * list, and rebuilding one from a stream of additions and removals is work the caller
     * should not repeat.
     */
    fun hosts(context: Context): Flow<List<SmbHost>> = callbackFlow {
        val manager = context.getSystemService(NsdManager::class.java)
        if (manager == null) {
            send(emptyList())
            close()
            return@callbackFlow
        }

        val found = LinkedHashMap<String, SmbHost>()

        val resolver = object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) = Unit

            override fun onServiceResolved(info: NsdServiceInfo) {
                // `host` is deprecated in favour of `hostAddresses`, which needs API 34.
                // This module's floor is 31, so the old one is the one that exists.
                @Suppress("DEPRECATION")
                val address = info.host?.hostAddress ?: return
                found[info.serviceName] = SmbHost(info.serviceName, address, info.port)
                trySend(found.values.toList())
            }
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, code: Int) { close() }
            override fun onStopDiscoveryFailed(type: String, code: Int) = Unit

            override fun onServiceFound(info: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                manager.resolveService(info, resolver)
            }

            override fun onServiceLost(info: NsdServiceInfo) {
                found.remove(info.serviceName)
                trySend(found.values.toList())
            }
        }

        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        awaitClose { runCatching { manager.stopServiceDiscovery(listener) } }
    }
}
