package app.storyarc.core.designsystem.control

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialExpressiveTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.SliderState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.brandLightScheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

/**
 * A slider at the start of its travel has its handle on the rail, not beside it.
 *
 * The sweep of 2026-09-02, §7: the page slider "draws its thumb as a tall vertical bar at the
 * far left, outside and above the rounded track that starts about 17 px to its right. It
 * reads as a rendering fault rather than a control." The same frame set shows Sharpness at
 * zero doing it in `android-comic-adjustments.png`, two rows under a Brightness slider at
 * mid-range that looks entirely right — which is the whole diagnosis: Material's gap has
 * nothing behind it when one half of the rail has no width.
 *
 * ## Why this draws pixels
 *
 * A test that asserted `thumbTrackGapSize == 0.dp` would be restating the call, and the
 * defect is not a number — it is a run of *page* between two parts of one control. Material's
 * default is private, so there is nothing to compare a number against either. So this draws
 * the slider twice at the same size, once through [StoryArcSliderTrack] and once through
 * `SliderDefaults.Track`, and counts the background-coloured pixels along the control's
 * centre line between the leftmost and rightmost pixels that belong to it. Material's leaves
 * a run; ours leaves none, and the second half of that pair is what stops the parameter being
 * silently dropped.
 *
 * `GraphicsMode.NATIVE` because legacy graphics draw nothing worth measuring — the same
 * reason the Compose suites in this module use it.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37. Nothing here has one either.
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(ExperimentalMaterial3Api::class)
class SliderTrackTouchesItsThumbTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun `the shared rail runs all the way to the handle`() {
        assertEquals(
            "There is a run of bare page between the handle and the rail, which is what the" +
                " sweep read as a rendering fault. `StoryArcSliderTrack` exists to close it.",
            0,
            gapPixels { state -> StoryArcSliderTrack(state) },
        )
    }

    @Test
    fun `Material's own rail is the one that leaves a gap`() {
        // The negative half. Without it the assertion above would keep passing on the day
        // material3 drops the gap itself, and nobody would learn that the override had
        // become a no-op — the same reason `AccentReachesTheControlsTest` asserts against
        // Material's baseline rather than only against the token.
        assertTrue(
            "Material's default track no longer leaves a gap at the start of the travel, so" +
                " `StoryArcSliderTrack` is now a no-op and can go.",
            gapPixels { state -> SliderDefaults.Track(sliderState = state) } > 0,
        )
    }

    /**
     * Bare page along the control's centre line, between its own leftmost and rightmost ink.
     *
     * The slider is drawn at its minimum, which is where both halves of the defect live: the
     * active rail has no width, so anything between the handle and the inactive rail is
     * page showing through a control.
     */
    private fun gapPixels(track: @Composable (SliderState) -> Unit): Int {
        compose.setContent {
            MaterialExpressiveTheme(colorScheme = brandLightScheme()) {
                Box(Modifier.background(PAGE).width(WIDTH).padding(horizontal = 16.dp)) {
                    Slider(
                        value = 0f,
                        onValueChange = {},
                        valueRange = 0f..2f,
                        steps = 1,
                        track = track,
                        modifier = Modifier.fillMaxWidth().testTag(TAG),
                    )
                }
            }
        }
        compose.waitForIdle()

        val pixels = compose.onNodeWithTag(TAG).captureToImage().toPixelMap()
        val row = pixels.height / 2
        val ink = (0 until pixels.width).filter { !isPage(pixels[it, row]) }
        assertTrue("the slider drew nothing at all", ink.size > 2)
        return (ink.first()..ink.last()).count { isPage(pixels[it, row]) }
    }

    /**
     * Whether a pixel is the page rather than the control.
     *
     * A tolerance rather than equality: the rail's rounded ends are anti-aliased, and a
     * single blended pixel either side of a real edge is not a gap. Six levels out of 255 is
     * far below the rail's own contrast against the page and far above the noise.
     */
    private fun isPage(colour: Color): Boolean =
        abs(colour.red - PAGE.red) < TOLERANCE &&
            abs(colour.green - PAGE.green) < TOLERANCE &&
            abs(colour.blue - PAGE.blue) < TOLERANCE

    private companion object {
        const val TAG = "slider"
        val WIDTH = 320.dp

        /** A page nothing in the scheme is close to, so "not the page" means "the control". */
        val PAGE = Color.White
        const val TOLERANCE = 6 / 255f
    }
}
