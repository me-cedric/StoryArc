package app.storyarc.feature.reader

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import app.storyarc.core.smb.SmbNetworkWatch

/**
 * Drops a stale SMB session the moment the path underneath it moves, rather than waiting for
 * a read against it to time out first.
 *
 * `network-share`'s *Network changes*: nothing used to watch for one at all. `SourceRetryTriggers`
 * collects the same kind of signal for the library's sources and deliberately stops while the
 * reader screen is open — this is the reader's own half, alive for exactly as long as a
 * session here could be open. A composable of its own, beside [ReaderScreen] rather than
 * inline in it, because that file is already at its line cap.
 */
@Composable
internal fun SmbNetworkWatchEffect() {
    val context = LocalContext.current
    DisposableEffect(context) {
        SmbNetworkWatch.start(context)
        onDispose { SmbNetworkWatch.stop(context) }
    }
}
