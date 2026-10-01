package app.storyarc.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale
import java.util.TimeZone

/**
 * Task 15.4: `moment` used `DateUtils.formatDateTime`, which moves the clock between 12-
 * and 24-hour with the context it is given, but still writes the month and day names from
 * `Locale.getDefault()`. Measured against a real `DateUtils` call on this host: a French
 * context read "Oct 1, 2026, 17:06" -- the hour right, the month English. `moment` now
 * takes the locale for the words and the device's clock setting for the hour.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceDetailMomentTest {

    /** 2025-09-04 15:33 UTC: an afternoon, so a 12-hour clock and a 24-hour one disagree. */
    private val epochMillis = 1_757_000_000_000L

    private fun inUtc(block: () -> Unit) {
        val previous = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        try {
            block()
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test
    fun `the month name follows the given locale, not the system default`() {
        val english = moment(Locale.US, epochMillis, is24Hour = false)
        val french = moment(Locale.FRANCE, epochMillis, is24Hour = true)

        assertTrue("expected an English month in \"$english\"", english.contains("Sep"))
        assertTrue("expected a French month in \"$french\"", french.contains("sept"))
        assertNotEquals(english, french)
    }

    @Test
    fun `the device's 24-hour setting decides the clock, whatever the locale`() = inUtc {
        val twentyFour = moment(Locale.US, epochMillis, is24Hour = true)
        val twelve = moment(Locale.US, epochMillis, is24Hour = false)

        assertTrue("a 24-hour clock read \"$twentyFour\"", twentyFour.contains("15:33"))
        assertFalse("a 24-hour clock read a day period: \"$twentyFour\"", twentyFour.contains("PM"))
        assertTrue("a 12-hour clock read \"$twelve\"", twelve.contains("3:33") && twelve.contains("PM"))
    }

    @Test
    fun `the same locale is deterministic`() {
        assertEquals(
            moment(Locale.GERMANY, epochMillis, is24Hour = true),
            moment(Locale.GERMANY, epochMillis, is24Hour = true),
        )
    }
}
