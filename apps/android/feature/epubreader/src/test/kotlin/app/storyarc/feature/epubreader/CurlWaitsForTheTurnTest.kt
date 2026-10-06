package app.storyarc.feature.epubreader

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `close-the-audited-gaps` task 8.12: the curl rolls onto the page that arrived, and only
 * when one did.
 *
 * Readium's `goForward` answers before the page moves and answers true at the last page, so
 * the curl took its "incoming" picture of the page the reader was leaving, and played at the
 * last page while nothing turned. The location is what changes when a page does.
 */
class CurlWaitsForTheTurnTest {

    @Test
    fun `a turn that moves the book reports a turn`() = runTest {
        val location = MutableStateFlow("page 4")

        assertTrue(movedTo(location) { location.value = "page 5" })
    }

    @Test
    fun `a turn at the last page, where nothing moves, reports none`() = runTest {
        val location = MutableStateFlow("page 9 of 9")

        assertFalse(movedTo(location) { /* the navigator answers true and stays put */ })
    }
}
