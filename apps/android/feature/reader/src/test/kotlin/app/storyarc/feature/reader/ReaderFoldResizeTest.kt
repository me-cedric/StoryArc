package app.storyarc.feature.reader

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.WindowSize
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.AppearanceMode
import app.storyarc.core.playback.SpokenAudio
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * D5, `native-experience` *Opening and closing the device*: a fold is a resize, and the reader
 * keeps the page, the open sheet and a playing voice across it.
 *
 * The app's activity handles the size change itself (`configChanges` in the manifest), so a fold
 * reaches the reader as a new window size in the same composition. That is what this test does:
 * the outer display, then the open one, then the outer one again.
 *
 * **Proved able to fail**, per AGENTS.md section 5: keying `ReaderScreen`'s `open()` effect on the
 * window width opened the publication again on each resize, and this test failed by name on the
 * voice, which the second `open()` silenced. Reverted. Before `Pager` kept the page being read
 * across a regroup, it failed on the last line: the device closed on page 1.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ReaderFoldResizeTest {

    @get:Rule
    val compose = createComposeRule()

    @get:Rule
    val folder = TemporaryFolder()

    /** A voice that was already speaking when the device folded. */
    private class Voice : SpokenAudio.Speaker {
        var ended = false
        override var speaking: SpokenAudio.Spoken? = SpokenAudio.Spoken(id = "sea-room", title = "Sea Room")
            private set
        override val kind: SpokenAudio.Kind = SpokenAudio.Kind.NARRATOR
        override fun endSpeaking() {
            ended = true
            speaking = null
        }
    }

    @Test
    fun `opening and closing the device keeps the page, the menu and the voice`() {
        val speaker = SpokenAudio()
        val model = FoldFixtures.model(folder.root, speaker = speaker)
        var size by mutableStateOf(OUTER)
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.WindowSize(size)) {
                StoryArcTheme(appearance = AppearanceMode.LIGHT, useDynamicColor = false, natural = false) {
                    ReaderScreen(viewModel = model, onClose = {})
                }
            }
        }
        // Page 1 drawn, so the open's own jump to the first page is behind the tap below.
        compose.loaded(model)

        // Page 2: on the open display it shares a spread with page 1, which is the case that
        // must hand page 2 back, not page 1, when the device closes again.
        compose.onRoot().performTouchInput { click(Offset(width - 4f, centerY)) }
        compose.waitUntil(timeoutMillis = 5_000) { compose.shows("Page 2 of 3") }

        // Registered after `open()`, which silences any voice already speaking (D18).
        val voice = Voice()
        speaker.register(voice)

        // A centre tap toggles the chrome, so tap only while it is down.
        if (!compose.shows("Menu")) compose.onRoot().performTouchInput { click(center) }
        compose.onNodeWithContentDescription("Menu").performClick()
        compose.onNodeWithText("Contents").assertExists()

        for (next in listOf(INNER, OUTER)) {
            size = next
            compose.waitForIdle()
            compose.onNodeWithText("Contents").assertExists()
            assertFalse("The voice ended when the window became $next.", voice.ended)
        }
        compose.waitUntil(timeoutMillis = 5_000) { compose.shows("Page 2 of 3") && !compose.shows("Page 1 of 3") }
    }

    private companion object {
        /** The Pixel Fold's outer display, 1080 x 2092 px at 420 dpi. */
        val OUTER = DpSize(411.dp, 797.dp)

        /** Its open display, 2208 x 1840 px at 420 dpi. */
        val INNER = DpSize(841.dp, 701.dp)
    }
}
