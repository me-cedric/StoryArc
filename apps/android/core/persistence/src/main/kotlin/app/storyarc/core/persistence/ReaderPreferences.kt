package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.ChangeStamps
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.ScrollOffsetMemory
import app.storyarc.core.model.ShelfMemory
import app.storyarc.core.model.ThemeScope
import app.storyarc.core.model.ThemeStamps
import kotlinx.serialization.json.Json

class ReaderPreferences(
    private val preferences: SharedPreferences,
    private val now: () -> Long = System::currentTimeMillis,
) {

    companion object {
        fun open(context: Context): ReaderPreferences =
            ReaderPreferences(
                context.getSharedPreferences("app.storyarc.reader", Context.MODE_PRIVATE),
            )

        /**
         * The one fit the whole library used to share.
         *
         * Read once, folded into the fixed-layout default, and removed. See [themes].
         */
        private const val LEGACY_FIT = "pageFit"
        private const val THEMES = "themes"
        private const val THEMES_CHANGED_AT = "themesChangedAt"
        private const val SCROLL_OFFSETS = "scrollOffsets"

        /**
         * Lenient about fields it does not know.
         *
         * A build that adds an axis must still read what an earlier build wrote, and
         * an older build reading a newer file should drop the field rather than the
         * whole theme.
         */
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }

    /**
     * Every reading theme the reader has chosen, per shelf and per scope.
     *
     * One blob rather than a key per shelf: the whole point of [ShelfMemory] is that
     * resolution walks from shelf to scope to built-in default, and a store that
     * scattered the entries across preference keys would have to reimplement that
     * walk. Unreadable stored data reads as no data — a theme is a preference, and
     * losing one is worth far less than refusing to open the book.
     *
     * It is also where the page fit is picked up from where it used to live. The fit was
     * one value for the whole library before `comic-reader`'s "persists per series" was
     * honoured, and a reader who had chosen fit-to-width would otherwise find every comic
     * they own back at fit-to-screen on the day they updated. So the old value becomes the
     * fixed-layout *default*: every shelf that has not been told otherwise inherits it,
     * which is exactly what "global" meant, and a shelf they set later keeps its own. The
     * old key is removed as it is folded in, so this happens once.
     */
    fun themes(): ShelfMemory {
        val memory = storedThemes()
        val fit = preferences.getString(LEGACY_FIT, null)
            ?.let { name -> runCatching { PageFit.valueOf(name) }.getOrNull() }
            ?: return memory
        val migrated = memory.settingDefault(
            memory.default(ThemeScope.FIXED_LAYOUT).copy(fit = fit),
            ThemeScope.FIXED_LAYOUT,
        )
        preferences.edit().remove(LEGACY_FIT).apply()
        save(migrated)
        return migrated
    }

    /** When each theme field last changed, by its filed name. `library-sync` task 3.5. */
    fun themesChangedAt(): Map<String, Long> =
        preferences.getString(THEMES_CHANGED_AT, null)
            ?.let { runCatching { json.decodeFromString<Map<String, Long>>(it) }.getOrNull() }
            .orEmpty()

    /** Writes what the reader changed, with each changed field stamped now. */
    fun save(memory: ShelfMemory) = save(memory, themesChangedAt())

    /** Writes themes with their moments, as a sync leaves them. See [ChangeStamps.restamped]. */
    fun save(memory: ShelfMemory, changedAt: Map<String, Long>) {
        val stamps = ChangeStamps.restamped(
            ThemeStamps.values(storedThemes()), themesChangedAt(),
            ThemeStamps.values(memory), changedAt, now(), ThemeStamps::default,
        )
        preferences.edit()
            .putString(THEMES, json.encodeToString(memory))
            .putString(THEMES_CHANGED_AT, json.encodeToString(stamps))
            .apply()
    }

    private fun storedThemes(): ShelfMemory =
        preferences.getString(THEMES, null)
            ?.let { runCatching { json.decodeFromString<ShelfMemory>(it) }.getOrNull() }
            ?: ShelfMemory()

    /** Where a continuous scroll sits within its current page, per publication. */
    fun scrollOffsets(): ScrollOffsetMemory =
        preferences.getString(SCROLL_OFFSETS, null)
            ?.let { runCatching { json.decodeFromString<ScrollOffsetMemory>(it) }.getOrNull() }
            ?: ScrollOffsetMemory()

    fun save(memory: ScrollOffsetMemory) {
        preferences.edit().putString(SCROLL_OFFSETS, json.encodeToString(memory)).apply()
    }
}
