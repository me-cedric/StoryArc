package app.storyarc.core.playback

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The glyph the shade's two outer buttons wear.
 *
 * The first test ties the glyph to the interval it draws. It fails if one of the two moves
 * without the other, which is the defect a numbered glyph invites.
 */
@OptIn(UnstableApi::class)
class SkipButtonsTest {

    @Test
    fun `the two intervals wear the numbers the platform draws for them`() {
        assertEquals(
            CommandButton.ICON_SKIP_BACK_15,
            skipIcon(SkipDirection.BACK, SkipIntervals.BACK_SECONDS),
        )
        assertEquals(
            CommandButton.ICON_SKIP_FORWARD_30,
            skipIcon(SkipDirection.FORWARD, SkipIntervals.FORWARD_SECONDS),
        )
    }

    @Test
    fun `an interval the platform draws no number for gets an arrow`() {
        assertEquals(CommandButton.ICON_SKIP_BACK, skipIcon(SkipDirection.BACK, 20))
        assertEquals(CommandButton.ICON_SKIP_FORWARD, skipIcon(SkipDirection.FORWARD, 45))
    }
}
