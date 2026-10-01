package app.storyarc.feature.library

import android.icu.text.RelativeDateTimeFormatter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale

/**
 * Task 15.4: "X minutes ago" used `DateUtils.getRelativeTimeSpanString`, which has no
 * locale parameter and reads `Locale.getDefault()` -- the per-app language override does
 * not move that, only the composition's configuration.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LocalizedRelativeTimeTest {

    private val now = 1_757_000_000_000L

    @Test
    fun `ten minutes ago reads in French`() {
        val tenMinutesAgo = now - 10 * 60 * 1_000

        val french = localizedRelativeTime(tenMinutesAgo, now, Locale.FRENCH)
        val english = localizedRelativeTime(tenMinutesAgo, now, Locale.US)

        assertEquals("il y a 10 minutes", french)
        assertEquals("10 minutes ago", english)
        assertNotEquals(french, english)
    }

    @Test
    fun `thirty seconds ago reads in French, at second granularity`() {
        val thirtySecondsAgo = now - 30_000

        val french = localizedRelativeTime(
            thirtySecondsAgo,
            now,
            Locale.FRENCH,
            finestUnit = RelativeDateTimeFormatter.RelativeUnit.SECONDS,
        )

        assertEquals("il y a 30 secondes", french)
    }

    @Test
    fun `a span finer than the requested unit floors to that unit`() {
        val thirtySecondsAgo = now - 30_000

        // Minutes is the default finest unit -- thirty seconds floors to zero of them,
        // which is what CachedNotice asks for: it never shows seconds.
        val french = localizedRelativeTime(thirtySecondsAgo, now, Locale.FRENCH)

        assertEquals("il y a 0 minute", french)
    }

    @Test
    fun `a span of months reads in months, not in weeks`() {
        val fiveMonthsAgo = now - 150L * 24 * 60 * 60 * 1_000

        assertEquals("5 months ago", localizedRelativeTime(fiveMonthsAgo, now, Locale.US))
    }

    @Test
    fun `a span of years reads in years`() {
        val twoYearsAgo = now - 2L * 365 * 24 * 60 * 60 * 1_000

        assertEquals("il y a 2 ans", localizedRelativeTime(twoYearsAgo, now, Locale.FRENCH))
    }
}
