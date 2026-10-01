package app.storyarc.feature.library

import android.icu.text.RelativeDateTimeFormatter
import android.text.format.DateUtils
import java.util.Locale

/**
 * "X ago", in the composition's own locale.
 *
 * `DateUtils.getRelativeTimeSpanString` takes no locale and reads `Locale.getDefault()`,
 * which `localization`'s per-app language override never moves -- the override reaches a
 * `Configuration`, and `Locale.getDefault()` stays the device's. `RelativeDateTimeFormatter`
 * takes the locale directly.
 *
 * [finestUnit] is how fine a bucket the caller wants: [CachedNotice] never shows seconds
 * (a shelf refresh is not worth announcing to the second), [CheckedNotice] does, and
 * handles the first few seconds as "just now" itself before falling back to this.
 */
internal fun localizedRelativeTime(
    epochMillis: Long,
    now: Long,
    locale: Locale,
    finestUnit: RelativeDateTimeFormatter.RelativeUnit = RelativeDateTimeFormatter.RelativeUnit.MINUTES,
): String {
    val elapsed = (now - epochMillis).coerceAtLeast(0)
    // Years and months as iOS's `.relative(presentation: .named)` states them, so a source
    // unchecked since spring reads "5 months ago" rather than "22 weeks ago". A month is 30
    // days here: the bucket only has to be the one a reader would name.
    val units = listOf(
        RelativeDateTimeFormatter.RelativeUnit.YEARS to DateUtils.DAY_IN_MILLIS * DAYS_IN_YEAR,
        RelativeDateTimeFormatter.RelativeUnit.MONTHS to DateUtils.DAY_IN_MILLIS * DAYS_IN_MONTH,
        RelativeDateTimeFormatter.RelativeUnit.WEEKS to DateUtils.WEEK_IN_MILLIS,
        RelativeDateTimeFormatter.RelativeUnit.DAYS to DateUtils.DAY_IN_MILLIS,
        RelativeDateTimeFormatter.RelativeUnit.HOURS to DateUtils.HOUR_IN_MILLIS,
        RelativeDateTimeFormatter.RelativeUnit.MINUTES to DateUtils.MINUTE_IN_MILLIS,
        RelativeDateTimeFormatter.RelativeUnit.SECONDS to DateUtils.SECOND_IN_MILLIS,
    )
    val finestIndex = units.indexOfFirst { it.first == finestUnit }
    val (unit, divisor) = units.take(finestIndex + 1).firstOrNull { elapsed >= it.second }
        ?: units[finestIndex]

    return RelativeDateTimeFormatter.getInstance(locale).format(
        (elapsed / divisor).toDouble(),
        RelativeDateTimeFormatter.Direction.LAST,
        unit,
    )
}

private const val DAYS_IN_YEAR = 365
private const val DAYS_IN_MONTH = 30
