package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The two decisions in probing a source: how long to wait, and what the answer means.
 *
 * iOS's `SourceProbeTests` asserts the same table, case for case.
 */
class SourceProbeTest {

    private val moment = 1_000L

    @Test
    fun `the backoff doubles from five seconds`() {
        assertEquals(5_000L, SourceProbe.delayAfter(1))
        assertEquals(10_000L, SourceProbe.delayAfter(2))
        assertEquals(20_000L, SourceProbe.delayAfter(3))
        assertEquals(40_000L, SourceProbe.delayAfter(4))
    }

    @Test
    fun `the backoff stops at five minutes, however long a source has been away`() {
        assertEquals(300_000L, SourceProbe.delayAfter(7))
        assertEquals(300_000L, SourceProbe.delayAfter(50))
        // A day of failures must not overflow into a wait nobody comes back from.
        assertEquals(300_000L, SourceProbe.delayAfter(100_000))
    }

    @Test
    fun `no failures is not a wait at all`() {
        assertEquals(0L, SourceProbe.delayAfter(0))
        assertEquals(0L, SourceProbe.delayAfter(-1))
    }

    @Test
    fun `a success connects`() {
        assertEquals(SourceConnectionState.Connected, SourceProbe.stateForStatus(200, moment, "x"))
        assertEquals(SourceConnectionState.Connected, SourceProbe.stateForStatus(204, moment, "x"))
    }

    @Test
    fun `a refused credential is the one state that asks the reader to act`() {
        val state = SourceProbe.stateForStatus(401, moment, "Sign-in needed")

        assertEquals(SourceConnectionState.Unauthorized("Sign-in needed"), state)
        assertTrue(state.needsUserAction)
    }

    @Test
    fun `anything else is unreachable, and asks nothing of the reader`() {
        listOf(404, 500, 502, 0).forEach { code ->
            val state = SourceProbe.stateForStatus(code, moment, "x")
            assertEquals("status $code", SourceConnectionState.Unreachable(moment), state)
            // "Offline is a normal state, not an error" — a grey indicator, never a red one.
            assertFalse("status $code", state.needsUserAction)
        }
    }

    @Test
    fun `a connection that never answered reads the same as a bad one`() {
        assertEquals(SourceConnectionState.Unreachable(moment), SourceProbe.stateForFailure(moment))
    }

    @Test
    fun `only a source that can be away is asked`() {
        assertFalse(SourceProbe.isRemote(SourceKind.LOCAL_FOLDER))
        assertTrue(SourceProbe.isRemote(SourceKind.NETWORK_SHARE))
        assertTrue(SourceProbe.isRemote(SourceKind.OPDS_CATALOG))
        assertTrue(SourceProbe.isRemote(SourceKind.KAVITA_SERVER))
    }
}
