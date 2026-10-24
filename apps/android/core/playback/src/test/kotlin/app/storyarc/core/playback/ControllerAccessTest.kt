package app.storyarc.core.playback

import androidx.media3.session.SessionCommand
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What a controller that connects to the exported service may do.
 *
 * Any app can connect. The shelf lists audiobook titles and cover paths, so only a trusted
 * controller may browse it. Every controller keeps the skip buttons and the player commands.
 *
 * Robolectric because a `SessionCommand` holds a `Bundle`.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class ControllerAccessTest {

    @Test
    fun `a trusted controller may browse the shelf`() {
        val commands = sessionCommands(browses = true)

        assertTrue(commands.contains(SessionCommand.COMMAND_CODE_LIBRARY_GET_LIBRARY_ROOT))
        assertTrue(commands.contains(SessionCommand.COMMAND_CODE_LIBRARY_GET_CHILDREN))
        assertTrue(commands.contains(SessionCommand(PlaybackService.COMMAND_SKIP_BACK, android.os.Bundle.EMPTY)))
    }

    @Test
    fun `any other app may skip but not browse`() {
        val commands = sessionCommands(browses = false)

        assertFalse(commands.contains(SessionCommand.COMMAND_CODE_LIBRARY_GET_LIBRARY_ROOT))
        assertFalse(commands.contains(SessionCommand.COMMAND_CODE_LIBRARY_GET_CHILDREN))
        assertFalse(commands.contains(SessionCommand.COMMAND_CODE_LIBRARY_GET_ITEM))
        assertTrue(commands.contains(SessionCommand(PlaybackService.COMMAND_SKIP_BACK, android.os.Bundle.EMPTY)))
        assertTrue(commands.contains(SessionCommand(PlaybackService.COMMAND_SKIP_FORWARD, android.os.Bundle.EMPTY)))
    }
}
