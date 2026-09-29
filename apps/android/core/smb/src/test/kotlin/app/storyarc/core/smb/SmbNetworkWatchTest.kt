package app.storyarc.core.smb

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [isChange] -- which default-network reports [SmbNetworkWatch] drops the open sessions on.
 *
 * Plain values stand in for `android.net.Network`, which a JVM test cannot build: the rule is
 * about identity, and any type with equality carries it.
 */
class SmbNetworkWatchTest {
    @Test
    fun `the report a callback makes when it is registered is not a change`() {
        assertFalse(isChange(previous = null, next = 100))
    }

    @Test
    fun `the same network reported again is not a change`() {
        assertFalse(isChange(previous = 100, next = 100))
    }

    @Test
    fun `a move to another network is a change`() {
        assertTrue(isChange(previous = 100, next = 101))
    }
}
