package app.storyarc.feature.library

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

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
}
