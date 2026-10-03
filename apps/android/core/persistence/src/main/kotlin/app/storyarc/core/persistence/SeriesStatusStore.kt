package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.PublicationStatus
import kotlinx.serialization.json.Json

/**
 * A status the reader set by hand, for a series whose source reports none.
 *
 * `library-browsing` (D36): "a reader may set a status for that series by hand" when "a
 * series' source reports no publication status at all". The reported half of a status lives
 * on [app.storyarc.core.model.Publication] itself, carried there at index time by
 * `KavitaCard.appliedTo`; this is the other half, since nothing a scan or a Kavita answer
 * produces can be re-indexed to recover a choice the reader made in the app.
 *
 * Keyed by series name rather than by [app.storyarc.core.model.PublicationIdentity]: a
 * status is a fact about a series, every member of which the library already groups by that
 * name (`SeriesShelfScreen.seriesShelfMembers`), and a per-publication key would have to be
 * written to every issue a series holds and kept in step as issues are added. The same
 * collision a shared series name across two sources could cause already exists for grouping
 * itself; this does not make it worse.
 *
 * iOS's `SeriesStatusStore` mirrors it.
 */
class SeriesStatusStore internal constructor(
    private val preferences: SharedPreferences,
) {
    companion object {
        private const val NAME = "app.storyarc.library.seriesStatus"
        private const val STATUSES = "statuses"

        fun open(context: Context): SeriesStatusStore =
            SeriesStatusStore(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /** Every status a reader has set by hand, keyed by series name. */
    fun all(): Map<String, PublicationStatus> =
        preferences.getString(STATUSES, null)
            ?.let { runCatching { json.decodeFromString<Map<String, PublicationStatus>>(it) }.getOrNull() }
            ?: emptyMap()

    /** Sets, or replaces, the status a reader chose for one series. */
    fun set(series: String, status: PublicationStatus) {
        write(all() + (series to status))
    }

    /** Clears the status a reader had set for one series, leaving it unset again. */
    fun clear(series: String) {
        write(all() - series)
    }

    private fun write(value: Map<String, PublicationStatus>) {
        preferences.edit().putString(STATUSES, json.encodeToString(value)).apply()
    }
}
