package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

/**
 * What a sync keeps on this device between runs: this install's id, and the conflicted copies
 * it merged but could not delete.
 *
 * `library-sync` task 3.1: each record in the document names the device that last changed it.
 * The id is made once per install and never leaves it except in the document. iOS's
 * `LibrarySyncState` keeps the same two values.
 */
class LibrarySyncState internal constructor(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): LibrarySyncState =
            LibrarySyncState(context.getSharedPreferences("app.storyarc.sync", Context.MODE_PRIVATE))

        private const val DEVICE = "deviceId"
        private const val MERGED_COPIES = "mergedCopies"
    }

    /** This install's id, made on first use. */
    fun deviceId(): String = preferences.getString(DEVICE, null) ?: UUID.randomUUID().toString().also {
        preferences.edit().putString(DEVICE, it).apply()
    }

    /** Conflicted copies already merged, as `name@version`. */
    fun mergedCopies(): Set<String> = preferences.getStringSet(MERGED_COPIES, null).orEmpty().toSet()

    fun saveMergedCopies(copies: Set<String>) {
        preferences.edit().putStringSet(MERGED_COPIES, copies).apply()
    }
}
