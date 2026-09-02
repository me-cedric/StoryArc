package app.storyarc.core.model

import kotlinx.coroutines.flow.asFlow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * When a regained network or a returning app asks an away source again, and when it must not.
 *
 * iOS's `SourceReachabilityTests` asserts the same cases, case for case.
 */
class SourceReachabilityTest {

    private val moment = 1_000L

    private fun source(state: SourceConnectionState) =
        Source(displayName = "Shelf", kind = SourceKind.KAVITA_SERVER, state = state)

    private val away = listOf(source(SourceConnectionState.Unreachable(moment)))

    // region The two occasions

    @Test
    fun `a regained network retries a source that is away`() {
        assertTrue(
            SourceReachability.shouldProbe(RetryTrigger.CONNECTIVITY_REGAINED, away, isReading = false),
        )
    }

    @Test
    fun `returning to the foreground retries a source that is away`() {
        assertTrue(
            SourceReachability.shouldProbe(RetryTrigger.RETURNED_TO_FOREGROUND, away, isReading = false),
        )
    }

    @Test
    fun `both occasions are one decision, not two`() {
        // `sources` grants the immediate retry to a regained network *and* to a returning
        // app. One gate for both is what keeps the reading guard below on both of them, so
        // every trigger is asserted through it rather than only the two named above.
        RetryTrigger.entries.forEach { trigger ->
            assertTrue("$trigger", SourceReachability.shouldProbe(trigger, away, isReading = false))
            assertFalse("$trigger", SourceReachability.shouldProbe(trigger, away, isReading = true))
        }
    }

    // endregion

    // region Nothing to reconnect

    @Test
    fun `nothing away is nothing to ask`() {
        val connected = listOf(source(SourceConnectionState.Connected))
        assertFalse(
            SourceReachability.shouldProbe(RetryTrigger.CONNECTIVITY_REGAINED, connected, isReading = false),
        )
        assertFalse(
            SourceReachability.shouldProbe(RetryTrigger.CONNECTIVITY_REGAINED, emptyList(), isReading = false),
        )
    }

    @Test
    fun `a source still connecting is not one that is away`() {
        // Connecting is not a verdict -- the library probes on appearance and a trigger
        // arriving in that window would put a second request per source on the network
        // beside the first.
        val connecting = listOf(source(SourceConnectionState.Connecting))
        assertFalse(
            SourceReachability.shouldProbe(RetryTrigger.CONNECTIVITY_REGAINED, connecting, isReading = false),
        )
    }

    @Test
    fun `a refused credential is not retried by a network coming back`() {
        // No amount of network makes a rejected key work. `sources` gives that state a
        // single action the reader takes, and probing it on every hop would relist it.
        val refused = listOf(source(SourceConnectionState.Unauthorized("Sign-in needed")))
        assertFalse(
            SourceReachability.shouldProbe(RetryTrigger.CONNECTIVITY_REGAINED, refused, isReading = false),
        )
    }

    @Test
    fun `one source away among several is enough to ask`() {
        val sources = listOf(
            source(SourceConnectionState.Connected),
            source(SourceConnectionState.Unreachable(moment)),
            source(SourceConnectionState.Connecting),
        )

        assertTrue(
            SourceReachability.shouldProbe(RetryTrigger.RETURNED_TO_FOREGROUND, sources, isReading = false),
        )
    }

    // endregion

    // region The reader is left alone

    @Test
    fun `no probe is scheduled while a reader is open`() {
        // `sources`' *Automatic recovery*: reconnecting "does not present a notification or
        // interrupt reading". This is the whole of that clause -- a requirement about *not*
        // doing something, so the assertion is that nothing was scheduled rather than that
        // something eventually was.
        //
        // Both triggers, because both arrive from the system rather than from a screen: a
        // dropped Wi-Fi mid-chapter and an app returning to a reader that was already open
        // are the two ways this happens.
        assertFalse(
            SourceReachability.shouldProbe(RetryTrigger.CONNECTIVITY_REGAINED, away, isReading = true),
        )
        assertFalse(
            SourceReachability.shouldProbe(RetryTrigger.RETURNED_TO_FOREGROUND, away, isReading = true),
        )
    }

    @Test
    fun `the reader outranks every other reason to probe`() {
        // Several sources away, both occasions, and still nothing: the guard is not a
        // tiebreak that a long enough outage overrules.
        val sources = listOf(
            source(SourceConnectionState.Unreachable(moment)),
            source(SourceConnectionState.Unreachable(moment - 86_400_000L)),
            source(SourceConnectionState.Connected),
        )

        RetryTrigger.entries.forEach { trigger ->
            assertFalse("$trigger", SourceReachability.shouldProbe(trigger, sources, isReading = true))
        }
    }

    // endregion

    // region What a monitor's report is worth

    @Test
    fun `only a path appearing where there was none is a regained connection`() {
        assertEquals(
            RetryTrigger.CONNECTIVITY_REGAINED,
            SourceReachability.triggerFor(hasNetwork = true, previously = false),
        )
    }

    @Test
    fun `a path that was already there is no trigger`() {
        // A monitor reports every path change: one Wi-Fi network swapped for another, an
        // interface coming up beside the one already carrying traffic, a VPN attaching.
        // Reading each as a regain turns "retries immediately, once" into a probe per hop.
        assertNull(SourceReachability.triggerFor(hasNetwork = true, previously = true))
    }

    @Test
    fun `losing the network is no trigger at all`() {
        assertNull(SourceReachability.triggerFor(hasNetwork = false, previously = true))
        assertNull(SourceReachability.triggerFor(hasNetwork = false, previously = false))
    }

    // endregion

    // region The observer over an injected signal

    @Test
    fun `a dropped and regained network produces exactly one trigger`() = runTest {
        assertEquals(listOf(RetryTrigger.CONNECTIVITY_REGAINED), collect(listOf(false, true)))
    }

    @Test
    fun `a monitor's opening report is not a regain`() {
        // The first thing a monitor says describes the network as it already is rather than
        // a change to it. Read as a regain it would probe every source a moment after the
        // library's own appearance probe already did.
        assertNull(SourceReachability.triggerFor(hasNetwork = true, previously = true))
    }

    @Test
    fun `a flapping network produces one trigger per regain and no more`() = runTest {
        // Eight reports and two regains: the run of `true` at the front is the network the
        // app started on, and the repeats inside each run are the hops a monitor reports
        // without the reader having been offline at all.
        val reports = listOf(true, true, false, false, true, true, false, true)

        assertEquals(
            listOf(RetryTrigger.CONNECTIVITY_REGAINED, RetryTrigger.CONNECTIVITY_REGAINED),
            collect(reports),
        )
    }

    @Test
    fun `a signal that never leaves the network alone produces nothing`() = runTest {
        assertTrue(collect(listOf(true, true, true)).isEmpty())
    }

    /**
     * The triggers an injected sequence of path reports produces.
     *
     * The signal is handed in, which is the whole point: no `ConnectivityManager`, no
     * network, and the same list of reports drives iOS's mirror of this case.
     */
    private suspend fun collect(reports: List<Boolean>): List<RetryTrigger> =
        SourceReachability.triggers(reports.asFlow()).toList()

    // endregion
}
