package app.storyarc.feature.epubreader

import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.setting
import app.storyarc.core.model.values
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a gesture on one axis slider puts that axis back to the preset's value.
 *
 * `reading-themes`, *Resetting an axis*:
 *
 * > **WHEN** a user long-presses or double-taps a slider
 * > **THEN** that axis returns to its preset value
 *
 * The axes were built and this gesture was not, on either platform, while the task list
 * said it was. Two cases carry the weight. The reset must touch **one** axis: a reset that
 * quietly restores everything is a worse defect than no reset. And it must be reachable
 * without the gesture, because `native-experience` requires a control to announce what it
 * does, and TalkBack, Switch Access and a keyboard cannot long-press.
 *
 * iOS mirrors this suite in `ThemeAxisResetTests`.
 */
class ThemeAxisResetTest {

    /**
     * What the reader has set, and what the screen would send to the view model.
     *
     * [resetAxis] is handed the same `onSet` the sliders drag through, so this fake is the
     * view model's own arithmetic: `set(axis, value)` is `change(axis, values.setting(axis,
     * value))`. Recording the axes as well as the values is what lets the second case say
     * *which* axis moved.
     */
    private class Sheet(var values: ThemeValues) {
        val moved = mutableListOf<ThemeAxis>()

        fun set(axis: ThemeAxis, value: Double) {
            moved += axis
            values = values.setting(axis, value)
        }
    }

    @Test
    fun `the gesture returns the axis to the preset's own value`() {
        val sheet = Sheet(ThemePreset.CALM.values.setting(ThemeAxis.LINE_SPACING, 2.4))

        resetAxis(ThemePreset.CALM, ThemeAxis.LINE_SPACING, sheet::set)

        assertEquals(
            "The reset left the axis where the reader had dragged it. `reading-themes`:" +
                " \"that axis returns to its preset value\".",
            ThemePreset.CALM.values.lineHeight,
            sheet.values.lineHeight,
            0.0,
        )
    }

    @Test
    fun `it returns that axis alone, and leaves every other one where the reader put it`() {
        val sheet = Sheet(
            ThemePreset.CALM.values
                .setting(ThemeAxis.LINE_SPACING, 2.4)
                .setting(ThemeAxis.MARGINS, 2.1)
                .setting(ThemeAxis.WORD_SPACING, 0.3),
        )

        resetAxis(ThemePreset.CALM, ThemeAxis.LINE_SPACING, sheet::set)

        assertEquals(
            "The reset did not reach the axis it was asked for.",
            ThemePreset.CALM.values.lineHeight,
            sheet.values.lineHeight,
            0.0,
        )
        assertEquals(
            "Resetting one axis moved the margins. This is the worst form the defect takes:" +
                " a reader who nudges the margins, then puts the line spacing back, must keep" +
                " the margins. `reading-themes` scopes the gesture to \"that axis\".",
            2.1,
            sheet.values.pageMargins,
            0.0,
        )
        assertEquals(
            "Resetting one axis moved the word spacing.",
            0.3,
            sheet.values.wordSpacing,
            0.0,
        )
        assertEquals(
            "The reset touched more than one axis. It sent: ${sheet.moved}.",
            listOf(ThemeAxis.LINE_SPACING),
            sheet.moved,
        )
    }

    @Test
    fun `the reset goes through the one path that preserves the reading position`() {
        val screen = code("ThemeAxesScreen.kt")

        assertTrue(
            "The reset no longer goes through `onSet`. That is the path a drag takes, and" +
                " the only one that reaches the view model, the stored theme and" +
                " `applyTheme`. A reset written any other way would move the reader.",
            screen.contains("onSet(axis, preset.values.value(axis))"),
        )

        val activity = code("EpubReaderActivity.kt")
        assertTrue(
            "The axes screen's `onSet` is no longer the view model's `set`, so the reset" +
                " never reaches `applyTheme`.",
            activity.contains("onSet = model::set"),
        )
        assertTrue(
            "`applyTheme` no longer captures the locator before the reflow and returns to" +
                " it afterwards. `reading-themes`: the reading position \"is preserved to" +
                " the paragraph across the repagination\".",
            activity.contains("val locator = navigator.currentLocator.value") &&
                activity.contains("navigator.go(locator, animated = false)"),
        )
    }

    @Test
    fun `an axis put back to the preset's own value stops deviating`() {
        val dragged = ThemePreset.CALM.values.setting(ThemeAxis.LINE_SPACING, 2.4)
        val moved = ReadingTheme(ThemePreset.CALM).deviating(ThemeAxis.LINE_SPACING, dragged)
        assertTrue("The drag did not mark the preset modified.", moved.isModified)

        val back = moved.deviating(ThemeAxis.LINE_SPACING, ThemePreset.CALM.values)

        assertFalse(
            "The reset put the axis back and still recorded it as a deviation. Calm keeps" +
                " the \"Modified\" caption and the whole-theme \"Restore Calm\" action stays" +
                " on screen with nothing left to restore. `reading-themes`, *Resetting the" +
                " preset that is already unmodified*: the action is \"absent rather than" +
                " present and doing nothing\".",
            back.isModified,
        )
    }

    @Test
    fun `resetting one axis leaves the other moved axis deviating`() {
        val dragged = ThemePreset.CALM.values
            .setting(ThemeAxis.LINE_SPACING, 2.4)
            .setting(ThemeAxis.MARGINS, 2.1)
        val moved = ReadingTheme(ThemePreset.CALM)
            .deviating(ThemeAxis.LINE_SPACING, dragged)
            .deviating(ThemeAxis.MARGINS, dragged)

        val reset = dragged.setting(ThemeAxis.LINE_SPACING, ThemePreset.CALM.values.lineHeight)
        val back = moved.deviating(ThemeAxis.LINE_SPACING, reset)

        assertEquals(
            "The reset changed the deviations of an axis it was not asked for. Only the" +
                " axis that went back to the preset's value stops deviating; the margins the" +
                " reader nudged still differ from Calm, so Calm is still modified and still" +
                " restorable.",
            setOf(ThemeAxis.MARGINS),
            back.deviations,
        )
    }

    @Test
    fun `the view model records the reset against the preset, not as one more move`() {
        val model = code("EpubReaderViewModel.kt")

        assertTrue(
            "`EpubReaderViewModel.change` still marks every move as a deviation without" +
                " looking at the value, so the two cases above prove nothing about the" +
                " screen. The reset then leaves the axis on the preset's own value and the" +
                " preset marked modified, and the whole-theme \"Restore\" action stays on" +
                " screen with nothing to restore. `ReadingTheme.deviating(axis, values)` is" +
                " the overload that decides by value.",
            model.contains("deviating(axis, values)"),
        )
    }

    @Test
    fun `a long press on the axis performs the reset`() {
        val screen = code("ThemeAxesScreen.kt")

        assertTrue(
            "No long press is attached to an axis. `reading-themes` asks for a long press" +
                " or a double tap.",
            screen.contains("detectTapGestures(") && screen.contains("onLongPress ="),
        )
    }

    @Test
    fun `an accessibility action performs the same reset, named from the catalogue`() {
        val screen = code("ThemeAxesScreen.kt")

        assertTrue(
            "The axis slider carries no custom accessibility action, so the reset is" +
                " reachable only by a gesture. TalkBack, Switch Access and a keyboard cannot" +
                " perform one. `native-experience` requires every control to announce what" +
                " it does.",
            screen.contains("CustomAccessibilityAction("),
        )
        assertTrue(
            "The accessibility action is not named from the string catalogue, so a reader" +
                " in French, German or Spanish hears English. `lint` proves the four" +
                " translations; this proves the action asks for them.",
            screen.contains("stringResource(R.string.theme_axis_reset)"),
        )
    }

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    /**
     * One source file of this module, with its comments removed.
     *
     * A tripwire rather than a proof, for the reason `ThemeSheetTest` gives: no JVM test can
     * press a Compose gesture, so these cases say the wiring is written and never that a
     * finger reached it. What the reset *does* is proved over [resetAxis] above.
     */
    private fun code(name: String): String {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/epubreader/$name")
        if (!file.isFile) {
            error("$name is not under ${module.absolutePath} — has it moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        return withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
    }
}
