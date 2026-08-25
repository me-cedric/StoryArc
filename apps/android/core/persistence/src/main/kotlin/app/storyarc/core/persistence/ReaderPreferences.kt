package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.ThemeMemory
import kotlinx.serialization.json.Json

class ReaderPreferences(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): ReaderPreferences =
            ReaderPreferences(
                context.getSharedPreferences("app.storyarc.reader", Context.MODE_PRIVATE),
            )

        private const val FIT = "pageFit"
        private const val THEMES = "themes"

        /**
         * Lenient about fields it does not know.
         *
         * A build that adds an axis must still read what an earlier build wrote, and
         * an older build reading a newer file should drop the field rather than the
         * whole theme.
         */
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }

    fun pageFit(): PageFit =
        preferences.getString(FIT, null)
            ?.let { name -> runCatching { PageFit.valueOf(name) }.getOrNull() }
            ?: PageFit.SCREEN

    fun save(fit: PageFit) {
        preferences.edit().putString(FIT, fit.name).apply()
    }

    /**
     * Every reading theme the reader has chosen, per shelf and per scope.
     *
     * One blob rather than a key per shelf: the whole point of [ThemeMemory] is that
     * resolution walks from shelf to scope to built-in default, and a store that
     * scattered the entries across preference keys would have to reimplement that
     * walk. Unreadable stored data reads as no data — a theme is a preference, and
     * losing one is worth far less than refusing to open the book.
     */
    fun themes(): ThemeMemory =
        preferences.getString(THEMES, null)
            ?.let { runCatching { json.decodeFromString<ThemeMemory>(it) }.getOrNull() }
            ?: ThemeMemory()

    fun save(memory: ThemeMemory) {
        preferences.edit().putString(THEMES, json.encodeToString(memory)).apply()
    }
}
