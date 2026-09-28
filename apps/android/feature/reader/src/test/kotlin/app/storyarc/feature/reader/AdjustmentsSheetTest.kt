package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the image-adjustment sheet offers every adjustment the reader is promised.
 *
 * `comic-reader`, *Adjustments available*:
 *
 * > **THEN** brightness, contrast, sharpness, colour inversion, and greyscale are available
 * > with a live preview
 *
 * `comic-reader`, *Cropping borders*:
 *
 * > **WHEN** a user enables border cropping
 * > **THEN** uniform white or black margins are detected and trimmed per page, and the user
 * > can disable it for a page that crops wrongly
 *
 * **This test exists because the same sheet was dead on iOS.** There the detection, the
 * excused pages and the four translations were all in place and no switch was drawn, so no
 * reader could turn trimming on. Eight tests asserted the detection on each platform.
 * Nothing asserted that a reader could reach it. This is the Android half of that guard, and
 * `AdjustmentsSheetTests` is the iOS half.
 *
 * **Why it reads the source text.** The honest test composes the sheet and reads the
 * switches, the way `ThemeSheetSemanticsTest` composes `StoryArcTheme`. This module has no
 * instrumented test source set, and the unit gate runs on every pull request. A guard that
 * runs beats a better one that does not. It is a tripwire, not a proof: it says the sheet
 * writes each value, never that a switch appeared.
 */
class AdjustmentsSheetTest {

    /**
     * The sheet's source, at the path the module's build script hands to the test JVM.
     *
     * Deliberately not discovered. Walking up from the working directory leaves the module:
     * this repository nests agent worktrees at `.claude/worktrees/<name>/`, so the walk climbs
     * out of the worktree under test and reads the parent checkout's copy.
     *
     * Comments are stripped before anything is matched, because every spelling below appears
     * in a comment somewhere and a guard that found one there would be measuring the
     * documentation.
     */
    private val code: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SHEET_SOURCE)
        if (!file.isFile) {
            error("$SHEET_SOURCE is not under ${module.absolutePath} — has the sheet moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    /**
     * Each adjustment, and the write that makes a control change it.
     *
     * The write rather than the label: a label can be drawn beside a control that changes
     * nothing, and that is the shape the iOS defect had.
     */
    private val controls = listOf(
        "brightness" to "copy(brightness =",
        "contrast" to "copy(contrast =",
        "sharpness" to "copy(sharpness =",
        "colour inversion" to "copy(isInverted =",
        "greyscale" to "copy(isGreyscale =",
        "border cropping" to "copy(cropsBorders =",
        "excusing this page from the crop" to "onChange = onCropThisPage",
    )

    @Test
    fun `every adjustment the scenario names has a control bound to it`() {
        for ((what, spelling) in controls) {
            assertTrue(
                "The adjustments sheet binds no control to $what — `$spelling` is nowhere in" +
                    " its source. `comic-reader` requires brightness, contrast, sharpness," +
                    " colour inversion and greyscale to be available, and border cropping to" +
                    " be something \"a user enables\" and can \"disable … for a page that" +
                    " crops wrongly\". A value nothing writes to is a feature no reader can" +
                    " reach.",
                code.contains(spelling),
            )
        }
    }

    /**
     * The per-page switch is offered only where there is a trim to excuse the page from.
     *
     * `comic-reader` scopes the exception to "a page that crops wrongly", and no page crops
     * wrongly while nothing crops at all.
     */
    @Test
    fun `the per-page exception is offered only while the series is being trimmed`() {
        assertTrue(
            "The adjustments sheet offers the per-page exception unconditionally." +
                " `comic-reader` scopes it to \"a page that crops wrongly\", and a switch" +
                " that excuses a page from a trim nobody asked for states a choice the" +
                " reader does not have.",
            code.contains("if (adjustments.cropsBorders) {"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        const val SHEET_SOURCE =
            "src/main/kotlin/app/storyarc/feature/reader/AdjustmentsSheet.kt"
    }
}
