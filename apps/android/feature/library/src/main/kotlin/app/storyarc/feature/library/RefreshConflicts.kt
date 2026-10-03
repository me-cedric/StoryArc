package app.storyarc.feature.library

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * The conflicts a Kavita source's own background refresh found, waiting to be told to the
 * reader.
 *
 * Task 2.9's corrected note: `ServerLibrary.read` calls `KavitaSync.pull` for every Kavita
 * source it refreshes -- not only the one whose browser is open -- and `pull` already
 * resolves and saves the merged record. What it used to throw away is the list of genuine
 * conflicts that merge found, so a conflict a background refresh resolved never reached the
 * `SyncConflictNotice` (D3) the series screen already shows for its own pull.
 *
 * Held here rather than in [LibraryViewModel], which is at its line cap and may not grow.
 * [LibraryScreen] reads this the same way it would read a field on the view model; the only
 * difference is which file the state lives in.
 */
object RefreshConflicts {
    private val _conflicts = MutableStateFlow<List<KavitaConflict>>(emptyList())
    val conflicts: StateFlow<List<KavitaConflict>> = _conflicts.asStateFlow()

    /** Adds what one refresh found. Call sites hand in every conflict a pull returned. */
    fun report(found: List<KavitaConflict>) {
        if (found.isEmpty()) return
        _conflicts.update { it + found }
    }

    /** The reader has answered -- kept the local position, or taken the server's. */
    fun clear() {
        _conflicts.value = emptyList()
    }
}
