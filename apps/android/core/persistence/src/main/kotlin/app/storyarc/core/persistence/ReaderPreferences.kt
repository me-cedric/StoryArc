package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.PageFit

/**
 * How the reader was left, remembered across launches.
 *
 * `comic-reader`: the fit choice "persists per series". Per series is not yet
 * possible — a series is a name inferred from a folder, not an entity anything can
 * be keyed on — so this is one setting for the reader. That is a smaller promise
 * than the spec makes, and it is the honest one until series exist.
 *
 * Separate from `LibraryPreferences` because it answers a different question, and
 * cheap enough that sharing a file would save nothing worth the confusion. iOS's
 * `ReaderPreferences` keeps the same value in `UserDefaults`.
 */
class ReaderPreferences(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): ReaderPreferences =
            ReaderPreferences(
                context.getSharedPreferences("app.storyarc.reader", Context.MODE_PRIVATE),
            )

        private const val FIT = "pageFit"
    }

    /**
     * The stored fit, or fit-to-screen.
     *
     * Stored as the enum's name rather than its ordinal: an ordinal is a position in
     * a source file, and reordering [PageFit] would silently change what a stored
     * preference means. A name that no longer exists falls back rather than
     * crashing the launch.
     */
    fun pageFit(): PageFit =
        preferences.getString(FIT, null)
            ?.let { name -> runCatching { PageFit.valueOf(name) }.getOrNull() }
            ?: PageFit.SCREEN

    fun save(fit: PageFit) {
        preferences.edit().putString(FIT, fit.name).apply()
    }
}
