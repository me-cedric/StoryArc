package app.storyarc.core.model

import java.util.UUID
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * A source a reader screen found unreachable while it was open, so the library applies the
 * same state the next time anything is watching, rather than still showing *Connected* for a
 * share whose path no longer reaches it.
 *
 * `network-share`'s *Network changes*, second clause: a stale session is already dropped the
 * moment the path underneath it moves ([SmbNetworkWatch] in `core:smb`), but nothing told the
 * library the share was gone, so a reader who left the reader open through a Wi-Fi-to-cellular
 * move came back to a source still reading *Available*. The reader learns this is a LAN move
 * cannot survive the moment its own re-opened read still fails with `SmbError.HostUnreachable`
 * -- that is the one failure this reports, not a refusal or a damaged file -- and here rather
 * than in `core:smb` or `feature:library` because a feature module never depends on another
 * feature module, and both the reader and the library already depend on this one.
 *
 * A [SharedFlow] rather than a [kotlinx.coroutines.flow.StateFlow]: this is a report of
 * something that happened, not a level a late collector should replay — a library screen with
 * nobody watching yet is a library screen the probe loop already covers on its own.
 */
object SourceReachabilityEvents {
    private val _unreachable = MutableSharedFlow<UUID>(extraBufferCapacity = 8)
    val unreachable: SharedFlow<UUID> = _unreachable.asSharedFlow()

    /** Reports that this source's path no longer reaches it. */
    fun reportUnreachable(sourceId: UUID) {
        _unreachable.tryEmit(sourceId)
    }
}
