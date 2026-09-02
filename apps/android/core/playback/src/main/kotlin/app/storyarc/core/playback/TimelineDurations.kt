package app.storyarc.core.playback

import androidx.media3.common.C
import androidx.media3.common.Timeline

/**
 * How long each item is, read off the only place media3 keeps them.
 *
 * `Player.getDuration()` answers for the item playing and there is no per-item API; the rest
 * are on a `Timeline`'s windows, which arrive as a timeline change once the source has been
 * read. A window with no duration yet reports `C.TIME_UNSET`, and that is
 * [PlaybackDuration.Unknown] rather than a zero — a part of zero length would be one a skip
 * passes straight over.
 *
 * **Here rather than twice.** Both sides of the process boundary need it: the app's
 * [AudiobookSource], to give a folder's parts their lengths, and [PlaybackService], to answer
 * the notification's own skip buttons. The two would have drifted a clause at a time, which
 * is the failure `PageOrdering` and `ZipReader` are mirrored deliberately to avoid.
 *
 * Not on [PlaybackTimeline], which is free of media3 on purpose: it is a mirror of iOS's own
 * arithmetic, and a decoder's type on it would end that.
 */
internal fun Timeline.partDurations(): List<PlaybackDuration> {
    val window = Timeline.Window()
    return (0 until windowCount).map { index ->
        val millis = getWindow(index, window).durationMs
        if (millis == C.TIME_UNSET || millis <= 0) {
            PlaybackDuration.Unknown
        } else {
            PlaybackDuration.Known(millis)
        }
    }
}
