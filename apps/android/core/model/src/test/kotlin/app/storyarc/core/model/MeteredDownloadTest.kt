package app.storyarc.core.model

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `offline-downloads`' *Overriding once* and *Wi-Fi only*, asserted case for case. iOS's
 * `MeteredDownloadTests` asserts the same cases.
 *
 * The clause that matters is "for that item only". Everything here is about keeping the
 * grant to one publication: a reader who agreed to spend data on one comic has not agreed to
 * release the queue behind it, and a rule that could not tell those apart would turn a single
 * confirmation into a standing permission.
 */
class MeteredDownloadTest {
    @Test
    fun `on a metered link an ungranted download is confirmed first`() {
        assertTrue(MeteredDownload.needsConfirmation(isMetered = true, isOverridden = false))
    }

    @Test
    fun `off a metered link nothing is asked`() {
        // The tap is the whole interaction it has always been.
        assertFalse(MeteredDownload.needsConfirmation(isMetered = false, isOverridden = false))
        assertFalse(MeteredDownload.needsConfirmation(isMetered = false, isOverridden = true))
    }

    @Test
    fun `a grant already given is not asked for twice`() {
        // Which is what makes Download work the second time a reader presses it.
        assertFalse(MeteredDownload.needsConfirmation(isMetered = true, isOverridden = true))
    }

    @Test
    fun `wifi-only holds a metered download that carries no grant`() {
        assertFalse(
            MeteredDownload.mayStart(wifiOnly = true, isMetered = true, isOverridden = false),
        )
    }

    @Test
    fun `the granted publication starts while the rest of the queue waits`() {
        // The whole of "proceeds for that item only": the same settings, the same
        // connection, and two different answers depending only on which download is asked
        // about.
        assertTrue(
            MeteredDownload.mayStart(wifiOnly = true, isMetered = true, isOverridden = true),
        )
        assertFalse(
            MeteredDownload.mayStart(wifiOnly = true, isMetered = true, isOverridden = false),
        )
    }

    @Test
    fun `wifi-only on wifi holds nothing`() {
        assertTrue(
            MeteredDownload.mayStart(wifiOnly = true, isMetered = false, isOverridden = false),
        )
    }

    @Test
    fun `with the setting off a metered download runs unasked-for permission`() {
        // The reader was still *confirmed* -- that is needsConfirmation's job, and it does
        // not consult the setting -- but nothing holds the queue afterwards.
        assertTrue(
            MeteredDownload.mayStart(wifiOnly = false, isMetered = true, isOverridden = false),
        )
    }
}
