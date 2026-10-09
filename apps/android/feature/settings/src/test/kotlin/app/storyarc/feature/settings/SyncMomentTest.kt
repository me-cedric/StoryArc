package app.storyarc.feature.settings

import android.content.Context
import android.content.res.Configuration
import androidx.test.core.app.ApplicationProvider
import java.util.Calendar
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `close-the-audited-gaps` 27.8: the sync status moment is one well-formed sentence in the
 * reader's language and region. The status once read "Synced at Jan 1, 2026 at 1:00": the word
 * "at" twice, and no AM or PM where the locale uses one.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncMomentTest {

    private val SPAIN = Locale.forLanguageTag("es-ES")

    private val now = at(2026, Calendar.OCTOBER, 10, 15, 30)

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0): Long =
        Calendar.getInstance().apply { clear(); set(year, month, day, hour, minute, second) }.timeInMillis

    private fun sentence(
        locale: Locale,
        atMillis: Long,
        is24Hour: Boolean = locale != Locale.US,
    ): String {
        val base: Context = ApplicationProvider.getApplicationContext()
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration).apply { setLocale(locale) },
        )
        return syncedSentence(localized, atMillis, now, locale, is24Hour)
            .replace(' ', ' ')
            .replace(' ', ' ')
    }

    @Test
    fun `under a minute ago is just now, in every language`() {
        val twenty = now - 20_000
        assertEquals("Synced just now", sentence(Locale.US, twenty))
        assertEquals("Synchronisé à l’instant", sentence(Locale.FRANCE, twenty))
        assertEquals("Gerade synchronisiert", sentence(Locale.GERMANY, twenty))
        assertEquals("Sincronizado hace un momento", sentence(SPAIN, twenty))
    }

    @Test
    fun `within the hour the platform writes the relative phrase`() {
        val fiveMinutes = now - 5 * 60_000
        assertEquals("Synced 5 minutes ago", sentence(Locale.US, fiveMinutes))
        assertEquals("Synchronisé il y a 5 minutes", sentence(Locale.FRANCE, fiveMinutes))
        assertEquals("Synchronisiert vor 5 Minuten", sentence(Locale.GERMANY, fiveMinutes))
        assertEquals("Sincronizado hace 5 minutos", sentence(SPAIN, fiveMinutes))
    }

    @Test
    fun `earlier today is the time of day on the locale's own clock`() {
        val morning = at(2026, Calendar.OCTOBER, 10, 9, 5)
        assertEquals("Synced today at 9:05 AM", sentence(Locale.US, morning, is24Hour = false))
        assertEquals("Synced today at 09:05", sentence(Locale.US, morning, is24Hour = true))
        assertEquals("Synchronisé aujourd’hui à 09:05", sentence(Locale.FRANCE, morning))
        assertEquals("Heute um 09:05 synchronisiert", sentence(Locale.GERMANY, morning))
    }

    @Test
    fun `an older sync is the date and time, with no second at`() {
        val january = at(2026, Calendar.JANUARY, 1, 13, 0)

        val english = sentence(Locale.US, january)
        assertTrue(english, english.startsWith("Synced on "))
        assertTrue(english, english.contains("Jan 1, 2026") && english.contains("1:00 PM"))
        assertFalse(english, english.contains(" at "))

        val french = sentence(Locale.FRANCE, january)
        assertTrue(french, french.startsWith("Synchronisé le "))
        assertTrue(french, french.contains("janv.") && french.contains("13:00"))
        assertFalse(french, french.contains("PM") || french.contains(" à "))
    }

    @Test
    fun `the age picks the sentence at each edge`() {
        assertEquals(SyncAge.JUST_NOW, syncAge(now - 59_999, now))
        assertEquals(SyncAge.MINUTES_AGO, syncAge(now - 60_000, now))
        assertEquals(SyncAge.MINUTES_AGO, syncAge(now - 3_599_999, now))
        assertEquals(SyncAge.TODAY, syncAge(now - 3_600_000, now))
        assertEquals(SyncAge.TODAY, syncAge(at(2026, Calendar.OCTOBER, 10, 9, 5), now))
        assertEquals(SyncAge.EARLIER, syncAge(at(2026, Calendar.OCTOBER, 9, 15, 30), now))
        assertEquals(SyncAge.JUST_NOW, syncAge(now + 5_000, now))
        val afterMidnight = at(2026, Calendar.OCTOBER, 10, 0, 30)
        assertEquals(SyncAge.MINUTES_AGO, syncAge(at(2026, Calendar.OCTOBER, 9, 23, 59), afterMidnight))
        assertEquals(SyncAge.EARLIER, syncAge(at(2026, Calendar.OCTOBER, 9, 22, 0), afterMidnight))
    }
}
