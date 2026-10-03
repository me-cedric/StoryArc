package app.storyarc.feature.reader

import app.storyarc.core.model.SourceReachabilityEvents
import app.storyarc.core.smb.SmbError

/**
 * `network-share`'s *Network changes*, second clause: the reader is the one place a path
 * change's own retry already runs, so it is the one place that already learns -- from
 * [SmbError.HostUnreachable], which `SmbSource.read` throws only once a reopened session has
 * also failed -- that the share it is reading is actually gone. [SourceReachabilityEvents]
 * carries that to the library, which has nothing open to read it back on otherwise.
 *
 * Beside [ReaderViewModel] rather than inside it: that file is close to its line cap, and a
 * cause-chain walk is a few lines it does not have to spend.
 */
internal fun ReaderViewModel.reportIfUnreachable(cause: Throwable) {
    val sourceId = publication.sourceId ?: return
    var current: Throwable? = cause
    var steps = 0
    while (current != null && steps < 20) {
        if (current is SmbError.HostUnreachable) {
            SourceReachabilityEvents.reportUnreachable(sourceId)
            return
        }
        val next = current.cause
        current = next.takeUnless { it === current }
        steps++
    }
}
