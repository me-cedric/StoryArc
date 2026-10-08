package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

/** Where the reader chose to keep the sync document. */
sealed interface SyncPlaceChoice {
    /** A share the reader already added, by its source id. */
    data class Share(val sourceId: UUID) : SyncPlaceChoice

    /** A folder picked through the system picker: a tree `Uri` with a persisted read and write grant. */
    data class Folder(val tree: String) : SyncPlaceChoice
}

/**
 * The sync place, on this device only.
 *
 * `library-sync` task 2.1. Not in `AppSettings`, because the settings travel in the sync document
 * and each device reaches the place by its own path. No choice means sync is off: nothing is
 * written, read or looked for. iOS's `SyncPlaceStore` keeps the same value.
 */
class SyncPlaceStore internal constructor(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): SyncPlaceStore =
            SyncPlaceStore(context.getSharedPreferences("app.storyarc.syncPlace", Context.MODE_PRIVATE))

        private const val PLACE = "place"
        private const val SHARE = "share:"
        private const val FOLDER = "folder:"
    }

    /** The chosen place, or null while sync is off. */
    fun choice(): SyncPlaceChoice? {
        val stored = preferences.getString(PLACE, null) ?: return null
        return when {
            stored.startsWith(SHARE) ->
                runCatching { UUID.fromString(stored.removePrefix(SHARE)) }.getOrNull()?.let(SyncPlaceChoice::Share)
            stored.startsWith(FOLDER) -> SyncPlaceChoice.Folder(stored.removePrefix(FOLDER))
            else -> null
        }
    }

    /** Stores [choice], or turns sync off with null. */
    fun choose(choice: SyncPlaceChoice?) {
        val stored = when (choice) {
            is SyncPlaceChoice.Share -> SHARE + choice.sourceId
            is SyncPlaceChoice.Folder -> FOLDER + choice.tree
            null -> null
        }
        preferences.edit().putString(PLACE, stored).apply()
    }
}
