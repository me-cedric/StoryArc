package app.storyarc.feature.reader

import android.graphics.Bitmap
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.doubleClick
import androidx.compose.ui.test.down
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.moveBy
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.up
import app.storyarc.core.model.CurlVerdict
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.PageFit
import app.storyarc.core.persistence.CurlCapability
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * That the curl stands over the reader's own page body, and that the body owns the finger.
 *
 * D33 (task 8.16): at rest Curl draws the normal page body, [ZoomablePage], with its fit,
 * its pinch and its marks, and a turn starts only from a finger the body leaves alone. So a
 * fitted page turns on a sideways drag, and a zoomed page pans instead. D10 (task 8.5): the
 * last page lifts off the end screen, which is drawn under it only while it lifts.
 *
 * Composed for real, with the body the reader uses, because this is a statement about which
 * of two pointer handlers wins, and only a composition answers that. API 32, below the
 * shader's floor: what is under test is the gesture, and the shader is not.
 *
 * iOS's `CurlOverThePageBodyTests` asserts the same rules through the arithmetic its host
 * tests can reach.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [32], qualifiers = "w360dp-h640dp")
class CurlOverThePageBodyTest {

    @get:Rule
    val compose = createComposeRule()

    /**
     * This device judged its curl already, so the frame clock does not run. An unjudged
     * device counts every frame of a turn with a callback that posts itself again, and a
     * drag held across an idle wait would then never let the test go idle.
     */
    @Before
    fun judgeTheDevice() {
        val capability = CurlCapability.open(RuntimeEnvironment.getApplication())
        repeat(CurlVerdict.TURNS) { capability.record(0.0) }
    }

    private var turned = 0
    private var zoomedTo = 1f
    private val page = Bitmap.createBitmap(360, 640, Bitmap.Config.ARGB_8888).asImageBitmap()

    private fun curl(beneath: Boolean = true, endsHere: Boolean = false) {
        compose.setContent {
            val progress = remember { Animatable(0f) }
            CurledPages(
                page = page.asAndroidBitmap(),
                beneath = if (beneath) Bitmap.createBitmap(360, 640, Bitmap.Config.ARGB_8888) else null,
                previous = null,
                isRightToLeft = false,
                matte = Color.Black,
                adjustments = ImageAdjustments(),
                isUnavailable = false,
                codecName = null,
                onTurned = { turned += 1 },
                onTurnedBack = {},
                progress = progress,
                modifier = Modifier.testTag(CURL),
                endsHere = endsHere,
                endScreen = { Box(Modifier.fillMaxSize().testTag(END)) },
                body = {
                    ZoomablePage(
                        bitmap = page,
                        pageId = "page",
                        contentDescription = "page",
                        fit = PageFit.SCREEN,
                        carriedZoomScale = null,
                        isRightToLeft = false,
                        adjustments = ImageAdjustments(),
                        onTap = { _, _ -> },
                        onZoom = { scale, _ -> zoomedTo = scale },
                    )
                },
            )
        }
    }

    @Test
    fun `a fitted page turns on a sideways drag over its own body`() {
        curl()

        compose.onNodeWithTag(CURL).performTouchInput { swipeLeft() }
        compose.waitForIdle()

        assertEquals("The drag over the page body did not turn the page.", 1, turned)
    }

    @Test
    fun `a zoomed page pans and does not turn`() {
        curl()
        compose.onNodeWithTag(CURL).performTouchInput { doubleClick(center) }
        // Past the settle the page waits before it reports a zoom.
        compose.mainClock.advanceTimeBy(ZOOM_SETTLE)
        compose.waitForIdle()
        assertTrue("The double-tap did not zoom the page, so this proves nothing.", zoomedTo > 1f)

        compose.onNodeWithTag(CURL).performTouchInput { swipeLeft() }
        compose.waitForIdle()

        assertEquals("A zoomed page turned instead of panning.", 0, turned)
    }

    @Test
    fun `the last page lifts off the end screen, drawn under it only while it lifts`() {
        curl(beneath = false, endsHere = true)
        compose.onNodeWithTag(END, useUnmergedTree = true).assertDoesNotExist()

        compose.onNodeWithTag(CURL).performTouchInput {
            down(Offset(width * 0.9f, height / 2f))
            moveBy(Offset(-width * 0.2f, 0f))
            moveBy(Offset(-width * 0.1f, 0f))
        }
        compose.waitForIdle()
        compose.onNodeWithTag(END, useUnmergedTree = true).assertExists()

        compose.onNodeWithTag(CURL).performTouchInput { moveBy(Offset(-width * 0.4f, 0f)); up() }
        compose.waitForIdle()
        assertEquals("Lifting the last page past halfway did not land on the end screen.", 1, turned)
    }

    @Test
    fun `mid-publication the end screen is never drawn`() {
        curl(beneath = true, endsHere = false)

        compose.onNodeWithTag(CURL).performTouchInput {
            down(Offset(width * 0.9f, height / 2f))
            moveBy(Offset(-width * 0.3f, 0f))
        }
        compose.waitForIdle()

        compose.onNodeWithTag(END, useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun `a page with nothing of any kind beneath it does not lift`() {
        curl(beneath = false, endsHere = false)

        compose.onNodeWithTag(CURL).performTouchInput { swipeLeft() }
        compose.waitForIdle()

        assertEquals(0, turned)
    }

    private companion object {
        const val CURL = "curl"
        const val END = "end"
        const val ZOOM_SETTLE = 2_000L
    }
}
