package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences

/**
 * How fast a listener likes a book read to them.
 *
 * `audio-playback`: the speed "is remembered for that publication and offered as the default
 * for others in the same series". Two scopes, resolved in that order, and a bare default
 * under both.
 *
 * **Why the series is written as well as the publication.** A listener who settles on 1.4×
 * for volume one has said something about the narrator, not about that file — and volume two
 * arriving at 1× would make them say it again for every book in the series. So a choice
 * writes both entries, and the publication's own always wins: adjusting volume two does not
 * reach back and change volume one.
 *
 * Keys rather than one serialised blob, unlike [ReaderPreferences.themes]: there is no walk
 * to reimplement here — two lookups and a default — and a key per publication is what lets a
 * library of five hundred books not rewrite a single document on every change.
 */
class PlaybackPreferences(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): PlaybackPreferences =
            PlaybackPreferences(
                context.getSharedPreferences("app.storyarc.playback", Context.MODE_PRIVATE),
            )

        /** Neither slower nor faster than the narrator recorded it. */
        const val NORMAL_SPEED: Double = 1.0

        private fun publicationKey(id: String) = "speed:publication:$id"

        private fun seriesKey(series: String) = "speed:series:$series"
    }

    /**
     * The speed to start this publication at.
     *
     * @param series what the publication belongs to, or null for one that belongs to nothing.
     */
    fun speed(publicationId: String, series: String?): Double {
        val own = preferences.getFloat(publicationKey(publicationId), 0f)
        if (own > 0f) return own.toDouble()
        val shared = series?.let { preferences.getFloat(seriesKey(it), 0f) } ?: 0f
        return if (shared > 0f) shared.toDouble() else NORMAL_SPEED
    }

    /** Remembers a speed for this publication, and offers it to the rest of the series. */
    fun rememberSpeed(publicationId: String, series: String?, rate: Double) {
        preferences.edit().apply {
            putFloat(publicationKey(publicationId), rate.toFloat())
            series?.let { putFloat(seriesKey(it), rate.toFloat()) }
        }.apply()
    }

    /**
     * Forgets every remembered speed.
     *
     * `settings-and-about` requires what the app remembers about reading to be clearable,
     * and a speed is one of those things. Deliberately whole-file: a listener clearing their
     * history does not mean "all but the series defaults".
     */
    fun clear() {
        preferences.edit().clear().apply()
    }
}
