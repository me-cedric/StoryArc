package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.DocumentConflict
import app.storyarc.core.model.ProgressPull
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
        private const val PENDING_CONFLICTS = "pendingConflicts"
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

    /**
     * The conflicts syncs found and the reader has not answered (task 5.9).
     *
     * A background sync runs in a process with no screen, and a notice held in memory went
     * with that process. These stay until the reader keeps or takes a position.
     */
    fun pendingConflicts(): List<ProgressPull.Conflict> =
        preferences.getString(PENDING_CONFLICTS, null)?.let(DocumentConflict::decode).orEmpty()

    fun savePendingConflicts(conflicts: List<ProgressPull.Conflict>) {
        preferences.edit().putString(PENDING_CONFLICTS, DocumentConflict.encode(conflicts)).apply()
    }
}
