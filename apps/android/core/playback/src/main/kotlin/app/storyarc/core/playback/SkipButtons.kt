package app.storyarc.core.playback

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton

/**
 * The glyph a skip control wears, wherever the platform draws one for us.
 *
 * media3 draws a numbered icon for a few intervals only, and a bare arrow for the rest. It
 * draws both of [SkipIntervals]. A button that moves twenty seconds and draws `15` is worse
 * than a button that draws an arrow, so a number this function does not know gets the arrow.
 *
 * Separate from [PlaybackService] so the mapping can be asserted without a service. The
 * icons are `@UnstableApi`, like everything else on media3's session surface.
 */
@OptIn(UnstableApi::class)
internal fun skipIcon(direction: SkipDirection, seconds: Int): Int = when (direction) {
    SkipDirection.BACK ->
        if (seconds == 15) CommandButton.ICON_SKIP_BACK_15 else CommandButton.ICON_SKIP_BACK
    SkipDirection.FORWARD ->
        if (seconds == 30) CommandButton.ICON_SKIP_FORWARD_30 else CommandButton.ICON_SKIP_FORWARD
}
