package app.storyarc.feature.library

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `network-share` "Local network permission denied", decision D25: SDK 37 gates SMB
 * discovery and the first connection to a share behind a runtime permission, and every
 * platform below it grants everything nothing ever asked for.
 *
 * Plain JUnit, no Robolectric: [LocalNetworkPermission.blocks] takes the SDK level and the
 * grant as plain values, so the rule is reachable without booting a fake platform for a
 * fictional SDK 37 that no shadow jar knows.
 */
class LocalNetworkPermissionTest {

    @Test
    fun `below SDK 37 nothing is blocked, granted or not`() {
        assertFalse(LocalNetworkPermission.blocks(sdkInt = 36, granted = false))
        assertFalse(LocalNetworkPermission.blocks(sdkInt = 31, granted = false))
    }

    @Test
    fun `at SDK 37 a missing grant blocks local network access`() {
        assertTrue(LocalNetworkPermission.blocks(sdkInt = 37, granted = false))
    }

    @Test
    fun `at SDK 37 a granted permission blocks nothing`() {
        assertFalse(LocalNetworkPermission.blocks(sdkInt = 37, granted = true))
    }

    @Test
    fun `the SDK 37 floor is exact, not a moment either side of it`() {
        assertFalse(LocalNetworkPermission.isRequired(sdkInt = 36))
        assertTrue(LocalNetworkPermission.isRequired(sdkInt = 37))
    }

    @Test
    fun `a refused permission does not stop a connection to a public server`() {
        assertFalse(LocalNetworkPermission.refuses(37, granted = false, url = "https://kavita.example.com/"))
        assertFalse(LocalNetworkPermission.refuses(37, granted = false, url = "https://8.8.8.8/opds"))
        assertTrue(LocalNetworkPermission.refuses(37, granted = false, url = "http://192.168.1.20:5000/"))
        assertFalse(LocalNetworkPermission.refuses(37, granted = true, url = "http://192.168.1.20:5000/"))
        assertFalse(LocalNetworkPermission.refuses(36, granted = false, url = "http://192.168.1.20:5000/"))
    }

    @Test
    fun `local addresses are private, link-local or unique-local literals, mDNS and bare names`() {
        listOf(
            "10.0.2.2", "172.16.0.1", "172.31.255.255", "192.168.1.20", "169.254.3.4",
            "[fe80::1]", "fd12:3456::1", "nas.local", "NAS.local.", "nas",
        ).forEach { assertTrue("$it is on the local network", LocalNetworkPermission.isLocal(it)) }
        listOf(
            "kavita.example.com", "8.8.8.8", "172.32.0.1", "172.15.0.1", "127.0.0.1",
            "localhost", "[::1]", "2001:db8::1", "", null,
        ).forEach { assertFalse("$it is not on the local network", LocalNetworkPermission.isLocal(it)) }
    }
}
