package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.ChangeStamps
import app.storyarc.core.model.SettingsStamps
import kotlinx.serialization.json.Json

/**
 * Where [AppSettings] lives between launches.
 *
 * Beside [ReaderPreferences] and `LibraryPreferences` rather than inside either.
 * `settings-and-about` groups settings by what a reader is looking for, and those groups
 * cut across the stores — appearance belongs to no reader and no library — so a third
 * store is the honest shape rather than a wing of one of the others.
 */
class SettingsStore(
    private val preferences: SharedPreferences,
    private val now: () -> Long = System::currentTimeMillis,
) {

    companion object {
        fun open(context: Context): SettingsStore =
            SettingsStore(context.getSharedPreferences("app.storyarc.settings", Context.MODE_PRIVATE))

        private const val SETTINGS = "settings"
        private const val CHANGED_AT = "settingsChangedAt"

        /**
         * Lenient about fields it does not know.
         *
         * A build that adds a setting must still read what an earlier build wrote, and an
         * older build reading a newer file should drop the field rather than the lot.
         */
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }

    /**
     * What the reader has chosen, or the defaults.
     *
     * Unreadable stored data reads as no data, the same rule the theme store uses: a
     * setting is a preference, and losing one is worth far less than refusing to start.
     */
    fun settings(): AppSettings =
        preferences.getString(SETTINGS, null)
            ?.let { runCatching { json.decodeFromString<AppSettings>(it) }.getOrNull() }
            ?: AppSettings.Defaults

    /** When each setting last changed, by field name. `library-sync` task 3.5. */
    fun changedAt(): Map<String, Long> =
        preferences.getString(CHANGED_AT, null)
            ?.let { runCatching { json.decodeFromString<Map<String, Long>>(it) }.getOrNull() }
            .orEmpty()

    /** Writes what the reader changed, with each changed field stamped now. */
    fun save(settings: AppSettings) = save(settings, changedAt())

    /**
     * Writes settings with their moments, as a sync leaves them. A field whose value changed
     * while its moment did not is stamped now; see [ChangeStamps.restamped].
     */
    fun save(settings: AppSettings, changedAt: Map<String, Long>) {
        val stamps = ChangeStamps.restamped(
            SettingsStamps.values(settings()), changedAt(),
            SettingsStamps.values(settings), changedAt, now(),
        )
        restore(settings, stamps)
    }

    /** Writes settings and moments exactly as given: the undo of a failed import or sync. */
    fun restore(settings: AppSettings, changedAt: Map<String, Long>) {
        val stamps = changedAt
        preferences.edit()
            .putString(SETTINGS, json.encodeToString(settings))
            .putString(CHANGED_AT, json.encodeToString(stamps))
            .apply()
    }

    /**
     * Puts everything this store holds back to its default.
     *
     * `settings-and-about` requires a reset to confirm first and to state that "sources,
     * downloads, and reading progress are not affected". That statement is true because
     * of what [AppSettings] *is*, not because this method is careful: it holds none of
     * them, so there is nothing here to be careful about.
     */
    fun reset() = save(AppSettings.Defaults)
}
