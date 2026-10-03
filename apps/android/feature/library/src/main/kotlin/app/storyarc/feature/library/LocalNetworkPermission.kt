package app.storyarc.feature.library

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.net.URI

/**
 * The runtime permission SDK 37 requires before this app may reach a TCP address on the
 * local network, resolve mDNS, or use `NsdManager`: discovery, and the first connection to
 * an SMB share, an OPDS catalogue, or a Kavita server (`network-share` "Local network
 * permission denied", decision D25). Below SDK 37 nothing gates any of this, so [blocks]
 * answers false there without asking the platform anything about a permission it has never
 * heard of.
 *
 * [blocks] is the pure half: a view or a view model asks the platform for the two booleans
 * once, and this decides. That is what lets a test reach it without a `Context`.
 */
object LocalNetworkPermission {
    const val PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"
    private const val REQUIRED_FROM_SDK = 37

    fun isRequired(sdkInt: Int = Build.VERSION.SDK_INT): Boolean = sdkInt >= REQUIRED_FROM_SDK

    fun isGranted(context: Context): Boolean =
        context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED

    /** Whether local-network access is blocked right now, for this platform and this grant. */
    fun blocks(sdkInt: Int, granted: Boolean): Boolean = isRequired(sdkInt) && !granted

    /**
     * Whether a connection to [url] waits on this permission. A public catalogue or Kavita
     * server never needs it, so a reader who refused local network access can still add one.
     */
    fun refuses(context: Context, url: String): Boolean =
        refuses(Build.VERSION.SDK_INT, isGranted(context), url)

    fun refuses(sdkInt: Int, granted: Boolean, url: String): Boolean =
        blocks(sdkInt, granted) && isLocal(runCatching { URI(url).host }.getOrNull())

    /**
     * Whether [host] names a device on the local network, from the address alone: a private,
     * link-local or unique-local literal, an mDNS `.local` name, or a single-label name.
     * ponytail: a public name that resolves to a LAN address is not caught here, and its
     * connect times out with the general sentence.
     */
    fun isLocal(host: String?): Boolean {
        val name = host?.removePrefix("[")?.removeSuffix("]")?.removeSuffix(".")?.lowercase()
        if (name.isNullOrEmpty() || name == "localhost") return false
        if (':' in name) {
            val first = name.substringBefore(':').toIntOrNull(HEX) ?: return false
            return first and 0xffc0 == 0xfe80 || first and 0xfe00 == 0xfc00
        }
        val octets = name.split('.').map { it.toIntOrNull() }
        if (octets.size == 4 && octets.all { it != null && it in 0..255 }) {
            val (a, b) = octets.map { it!! }
            return a == 10 || a == 172 && b in 16..31 || a == 192 && b == 168 || a == 169 && b == 254
        }
        return name.endsWith(".local") || '.' !in name
    }

    private const val HEX = 16
}
