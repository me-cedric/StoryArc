package app.storyarc.core.playback

import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The glyph the shade's two outer buttons wear.
 *
 * Every offered interval has a numbered icon, which is the argument for the set being what
 * it is; anything else gets an arrow rather than a number that lies about the interval.
 */
@OptIn(UnstableApi::class)
class SkipButtonsTest {

    @Test
    fun `every offered interval has a numbered glyph in both directions`() {
        val generic = setOf(CommandButton.ICON_SKIP_BACK, CommandButton.ICON_SKIP_FORWARD)
        for (seconds in SkipIntervals.OFFERED_SECONDS) {
            for (direction in SkipDirection.entries) {
                val icon = skipIcon(direction, seconds)
                assertEquals(
                    "$direction $seconds fell back to an arrow",
                    false,
                    icon in generic,
                )
            }
        }
    }

    @Test
    fun `the defaults wear the numbers design_md chose`() {
        assertEquals(CommandButton.ICON_SKIP_BACK_15, skipIcon(SkipDirection.BACK, 15))
        assertEquals(CommandButton.ICON_SKIP_FORWARD_30, skipIcon(SkipDirection.FORWARD, 30))
    }

    @Test
    fun `an interval the platform draws no number for gets an arrow`() {
        assertEquals(CommandButton.ICON_SKIP_BACK, skipIcon(SkipDirection.BACK, 20))
        assertEquals(CommandButton.ICON_SKIP_FORWARD, skipIcon(SkipDirection.FORWARD, 45))
    }
}
