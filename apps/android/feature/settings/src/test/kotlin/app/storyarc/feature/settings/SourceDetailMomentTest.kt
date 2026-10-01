package app.storyarc.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * Task 15.4: `moment` used `DateUtils.formatDateTime`, which moves the clock between 12-
 * and 24-hour with the context it is given, but still writes the month and day names from
 * `Locale.getDefault()`. Measured against a real `DateUtils` call on this host: a French
 * context read "Oct 1, 2026, 17:06" -- the hour right, the month English. `moment` now
 * takes the locale directly and writes both from it.
 */
class SourceDetailMomentTest {

    private val epochMillis = 1_757_000_000_000L

    @Test
    fun `the month name follows the given locale, not the system default`() {
        val english = moment(Locale.US, epochMillis)
        val french = moment(Locale.FRANCE, epochMillis)

        assertTrue("expected an English month in \"$english\"", english.contains("Sep"))
        assertTrue("expected a French month in \"$french\"", french.contains("sept"))
        assertNotEquals(english, french)
    }

    @Test
    fun `the same locale is deterministic`() {
        assertEquals(moment(Locale.GERMANY, epochMillis), moment(Locale.GERMANY, epochMillis))
    }
}
