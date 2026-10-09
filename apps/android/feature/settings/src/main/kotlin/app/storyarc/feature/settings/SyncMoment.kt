package app.storyarc.feature.settings

import android.content.Context
import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.ULocale
import android.text.format.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.floor

/**
 * How long ago a sync was, which picks the sentence. Each sentence is whole in every language,
 * because the word order of "Synced 5 minutes ago" is not the word order of "Synchronisé il y a
 * 5 minutes". `close-the-audited-gaps` 27.8.
 */
internal enum class SyncAge(val sentence: Int) {
    JUST_NOW(R.string.sync_status_synced_now),
    MINUTES_AGO(R.string.sync_status_synced_ago),
    TODAY(R.string.sync_status_synced_today),
    EARLIER(R.string.sync_status_synced_on),
}

private const val MINUTE = 60_000L
private const val HOUR = 60 * MINUTE

internal fun syncAge(atEpochMillis: Long, nowEpochMillis: Long): SyncAge {
    val age = nowEpochMillis - atEpochMillis
    return when {
        age < MINUTE -> SyncAge.JUST_NOW
        age < HOUR -> SyncAge.MINUTES_AGO
        isSameDay(atEpochMillis, nowEpochMillis) -> SyncAge.TODAY
        else -> SyncAge.EARLIER
    }
}

/**
 * The sync status sentence for a sync at [atEpochMillis], in the reader's language and region.
 *
 * The platform writes every moment: a relative phrase for the last hour, the time of day with the
 * device's own 12 or 24 hour clock for today, and the date and time for anything older. The
 * sentence around it is this app's, one whole string for each of those cases.
 */
internal fun syncedSentence(
    context: Context,
    atEpochMillis: Long,
    nowEpochMillis: Long = System.currentTimeMillis(),
    locale: Locale = context.resources.configuration.locales[0],
    is24Hour: Boolean = DateFormat.is24HourFormat(context),
): String {
    val age = syncAge(atEpochMillis, nowEpochMillis)
    return when (age) {
        SyncAge.JUST_NOW -> context.getString(age.sentence)
        SyncAge.MINUTES_AGO -> context.getString(age.sentence, minutesAgo(locale, nowEpochMillis - atEpochMillis))
        SyncAge.TODAY -> context.getString(age.sentence, timeOfDay(locale, atEpochMillis, is24Hour))
        SyncAge.EARLIER -> context.getString(age.sentence, moment(locale, atEpochMillis, is24Hour))
    }
}

private fun minutesAgo(locale: Locale, ageMillis: Long): String = RelativeDateTimeFormatter
    .getInstance(ULocale.forLocale(locale))
    .format(floor(ageMillis / MINUTE.toDouble()), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.MINUTES)

private fun timeOfDay(locale: Locale, epochMillis: Long, is24Hour: Boolean): String {
    val pattern = DateFormat.getBestDateTimePattern(locale, if (is24Hour) "Hm" else "hm")
    return SimpleDateFormat(pattern, locale).format(Date(epochMillis))
}

private fun isSameDay(first: Long, second: Long): Boolean {
    val a = Calendar.getInstance().apply { timeInMillis = first }
    val b = Calendar.getInstance().apply { timeInMillis = second }
    return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
}
