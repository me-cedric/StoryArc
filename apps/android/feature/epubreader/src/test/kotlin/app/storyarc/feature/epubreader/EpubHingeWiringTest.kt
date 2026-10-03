package app.storyarc.feature.epubreader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That `EpubReaderActivity` actually hands `container` the layout [epubHingeLayout] works
 * out, rather than leaving it at the plain match-parent it had before 19.5.
 *
 * [EpubHingeLayoutTest] pins the arithmetic on a plain JVM. It cannot pin the wiring — a
 * `Posture` from a folded device is not a Robolectric shadow this repository has reached
 * for, so this reads the activity's own source instead, in the manner of
 * `ReaderChromeWiringTest` and `CurlSheetWiringTest` over in `feature/reader`. It asserts
 * the call is written, not that a real fold moves the navigator; that is a manual or an
 * instrumented check on the day this module gets one.
 */
class EpubHingeWiringTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val source: String by lazy {
        val file = File(module, ACTIVITY_SOURCE)
        if (!file.isFile) error("$ACTIVITY_SOURCE is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    @Test
    fun `the activity keeps its navigator off the hinge`() {
        assertTrue(
            "EpubReaderActivity no longer calls KeepOffHinge(container) — the navigator stays" +
                " match-parent across a hinge it should have moved clear of.",
            source.contains("KeepOffHinge(container)"),
        )
    }

    @Test
    fun `KeepOffHinge re-sets the navigator's layout params from the window's hinge`() {
        val layout = File(module, LAYOUT_SOURCE).readText()
        assertTrue(
            "KeepOffHinge no longer reads windowPosture.separatingVerticalHingeBounds.",
            layout.contains("separatingVerticalHingeBounds.firstOrNull()"),
        )
        assertTrue(
            "KeepOffHinge no longer sets the container's layout params from epubHingeLayout.",
            layout.contains("container.layoutParams = epubHingeLayout(") && layout.contains("container.requestLayout()"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val ACTIVITY_SOURCE = "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt"
        const val LAYOUT_SOURCE = "src/main/kotlin/app/storyarc/feature/epubreader/EpubHingeLayout.kt"
    }
}
