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

    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, ACTIVITY_SOURCE)
        if (!file.isFile) error("$ACTIVITY_SOURCE is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    @Test
    fun `the activity reads the window's own separating vertical hinge`() {
        assertTrue(
            "EpubReaderActivity no longer reads windowPosture.separatingVerticalHingeBounds" +
                " — a folded window has nothing to avoid the hinge with.",
            source.contains("separatingVerticalHingeBounds.firstOrNull()"),
        )
    }

    @Test
    fun `the navigator's own layout params are replaced from the hinge split`() {
        assertTrue(
            "EpubReaderActivity no longer sets container.layoutParams from" +
                " epubHingeLayout(split).asLayoutParams() — the navigator stays" +
                " match-parent across a hinge it should have moved clear of.",
            source.contains("container.layoutParams = epubHingeLayout(split).asLayoutParams()"),
        )
        assertTrue(
            "The navigator's container is no longer asked to re-measure after its layout" +
                " params change, so a later fold would never move it.",
            source.contains("container.requestLayout()"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val ACTIVITY_SOURCE = "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderActivity.kt"
    }
}
