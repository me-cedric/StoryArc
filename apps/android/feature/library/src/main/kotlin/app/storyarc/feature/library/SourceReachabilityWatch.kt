package app.storyarc.feature.library

import androidx.lifecycle.viewModelScope
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceReachabilityEvents
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Applies a reader-reported "this share is gone" event to the live registry the moment it
 * arrives -- task 5.12's second clause.
 *
 * Beside [LibraryViewModel] rather than inside it: that file is at its line cap
 * (`scripts/line-cap.mjs`) and may not grow, the same reason [RefreshConflicts] and
 * [ServerLibrary] are beside it rather than inside it. Started once from
 * [LibraryViewModel.restoreFolders], the same "once, when the library first appears" moment
 * [LibraryViewModel.readServers] is first called from.
 */
internal fun LibraryViewModel.watchSourceReachability() {
    viewModelScope.launch {
        SourceReachabilityEvents.unreachable.collect { sourceId ->
            // The reader asks again every few seconds while the share is away. The first
            // report is when it went, so a later one leaves that moment alone.
            _registry.update { registry ->
                if (registry[sourceId]?.state is SourceConnectionState.Unreachable) {
                    registry
                } else {
                    registry.marking(sourceId, SourceConnectionState.Unreachable(System.currentTimeMillis()))
                }
            }
        }
    }
}
