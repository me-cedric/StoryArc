package app.storyarc.core.playback

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton

/**
 * The glyph a skip control wears, wherever the platform draws one for us.
 *
 * media3 ships a numbered icon for 5, 10, 15 and 30 seconds in each direction and a bare
 * arrow for everything else. [SkipIntervals.OFFERED_SECONDS] is that set for exactly this
 * reason: a notification button that moves twenty seconds and draws `15` is worse than one
 * that draws an arrow, and worse again than not offering twenty.
 *
 * Separate from [PlaybackService] so the mapping can be asserted without a service. The
 * icons are `@UnstableApi`, like everything else on media3's session surface.
 */
@OptIn(UnstableApi::class)
internal fun skipIcon(direction: SkipDirection, seconds: Int): Int = when (direction) {
    SkipDirection.BACK -> when (seconds) {
        5 -> CommandButton.ICON_SKIP_BACK_5
        10 -> CommandButton.ICON_SKIP_BACK_10
        15 -> CommandButton.ICON_SKIP_BACK_15
        30 -> CommandButton.ICON_SKIP_BACK_30
        // An arrow with no number rather than a number that is not the interval.
        else -> CommandButton.ICON_SKIP_BACK
    }
    SkipDirection.FORWARD -> when (seconds) {
        5 -> CommandButton.ICON_SKIP_FORWARD_5
        10 -> CommandButton.ICON_SKIP_FORWARD_10
        15 -> CommandButton.ICON_SKIP_FORWARD_15
        30 -> CommandButton.ICON_SKIP_FORWARD_30
        else -> CommandButton.ICON_SKIP_FORWARD
    }
}
