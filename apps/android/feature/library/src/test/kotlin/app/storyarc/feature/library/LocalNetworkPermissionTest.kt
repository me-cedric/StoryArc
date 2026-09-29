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
}
