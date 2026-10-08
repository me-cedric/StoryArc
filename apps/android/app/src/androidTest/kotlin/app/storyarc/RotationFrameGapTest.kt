package app.storyarc

import android.app.UiAutomation
import android.util.Base64
import android.util.Log
import android.view.Choreographer
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * Task 21.1 -- rotating the library page must not freeze the app.
 *
 * The field report was a 3305 ms `finishDrawing` after a rotation of the library page. This
 * seeds [LIBRARY_SIZE] one-page comics into the app's own files directory, opens the library,
 * turns the screen four times and records the longest gap between two frames the main thread
 * produced. A `Choreographer` callback that re-posts itself asks for a frame on every vsync,
 * so a gap is time the main thread spent on one rotation and nothing else.
 *
 * The bound is the one the task set. This is a debug build on an unthrottled Pixel 6a emulator,
 * where the longest gap was 0.07 to 0.75 s with the shelf moving across the rotation and 0.07
 * to 1.2 s without it, so one run cannot tell the two apart. The A/B that can is a release
 * build with six busy loops on the emulator's four cores: 0.28 to 0.63 s with the movable
 * pane, 1.0 to 4.7 s in five of six first rotations without it. `RotationShelfWiringTest`
 * holds the wiring on the host. Run this one on a throttled emulator when a trace is needed.
 */
class RotationFrameGapTest {

    @get:Rule
    val compose = createEmptyComposeRule()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val library: File =
        checkNotNull(instrumentation.targetContext.getExternalFilesDir(null)) { "No external files directory." }
    private val seeded = mutableListOf<File>()

    @After
    fun putTheDeviceBack() {
        instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE)
        seeded.forEach { it.delete() }
    }

    @Test
    fun rotatingALargeLibraryNeverHoldsTheMainThreadForLong() {
        seedLibrary()
        ActivityScenario.launch(MainActivity::class.java).use {
            compose.waitUntil(LAUNCH_MILLIS) {
                compose.onAllNodes(hasText("Library")).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("Library").performClick()
            Thread.sleep(SETTLE_MILLIS)

            val gap = FrameGap()
            // One turn there and back first, so the first scan of the seeded files and the first
            // run of cold code are not counted.
            instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_FREEZE_90)
            Thread.sleep(SETTLE_MILLIS)
            instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_FREEZE_0)
            Thread.sleep(SETTLE_MILLIS)
            instrumentation.runOnMainSync { gap.start() }
            val perRotation = ROTATIONS.map { rotation ->
                instrumentation.uiAutomation.setRotation(rotation)
                Thread.sleep(SETTLE_MILLIS)
                gap.takeLongest()
            }
            instrumentation.runOnMainSync { gap.stop() }
            Log.i("RotationFrameGap", "longest gap per rotation: $perRotation")

            assertTrue(
                "A rotation held the main thread for ${perRotation.max()} ms (every rotation: $perRotation); " +
                    "the bound is $BOUND_MILLIS ms.",
                perRotation.max() <= BOUND_MILLIS,
            )
        }
    }

    /** One tiny, distinct comic per file: a publication's identity is its content digest. */
    private fun seedLibrary() {
        val page = Base64.decode(ONE_PIXEL_PNG, Base64.DEFAULT)
        repeat(LIBRARY_SIZE) { index ->
            val file = File(library, "Rotation Series ${index / SERIES_LENGTH} ${index % SERIES_LENGTH + 1}.cbz")
            ZipOutputStream(file.outputStream()).use { zip ->
                zip.putNextEntry(ZipEntry("001.png"))
                zip.write(page)
                zip.putNextEntry(ZipEntry("ComicInfo.xml"))
                zip.write("<ComicInfo><Number>$index</Number></ComicInfo>".toByteArray())
            }
            seeded += file
        }
    }

    /** The gaps between two frames, in milliseconds, while [start] has run and [stop] has not. */
    private class FrameGap : Choreographer.FrameCallback {
        @Volatile private var millis = 0L
        private var last = 0L
        private var running = false

        /** The longest gap since the last call, which then starts again from nothing. */
        fun takeLongest(): Long = millis.also { millis = 0L }

        fun start() {
            running = true
            Choreographer.getInstance().postFrameCallback(this)
        }

        fun stop() {
            running = false
        }

        override fun doFrame(frameTimeNanos: Long) {
            if (last != 0L) millis = maxOf(millis, (frameTimeNanos - last) / NANOS_PER_MILLI)
            last = frameTimeNanos
            if (running) Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private companion object {
        const val LIBRARY_SIZE = 240
        const val SERIES_LENGTH = 6
        const val BOUND_MILLIS = 700L
        const val SETTLE_MILLIS = 2_000L
        const val LAUNCH_MILLIS = 30_000L
        const val NANOS_PER_MILLI = 1_000_000L
        const val ONE_PIXEL_PNG =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        val ROTATIONS = listOf(
            UiAutomation.ROTATION_FREEZE_90,
            UiAutomation.ROTATION_FREEZE_0,
            UiAutomation.ROTATION_FREEZE_90,
            UiAutomation.ROTATION_FREEZE_0,
        )
    }
}
