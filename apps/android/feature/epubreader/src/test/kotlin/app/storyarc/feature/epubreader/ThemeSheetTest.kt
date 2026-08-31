package app.storyarc.feature.epubreader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the theme surface has two levels, that level one is only presets, that level two is a
 * destination, and that the reset on it names what it restores.
 *
 * `ebook-reader`, *The theme surface opens on the presets*:
 *
 * > **THEN** the six preset swatches are what is shown, with no axis control among them
 * > **AND** one action, given equal prominence to the grid, opens the axes
 * > **AND** picking a preset applies it and leaves the surface, because that was the whole
 * > errand
 *
 * `ThemeResetTest` in `:core:model` owns what a reset *does*, over the pure type, and it
 * found a real defect doing it. This owns where the two levels are *drawn* and which controls
 * are on which — which no JVM test can measure, so it reads the source and is a tripwire
 * rather than a proof. It says level one declares no slider; it never says a slider failed to
 * appear.
 *
 * **Why the absence is the assertion.** The whole change is that nine sliders stopped being
 * the first thing a reader met. Nothing in a compiler notices one coming back, and the file
 * they would come back to is the one that used to hold them.
 *
 * iOS keeps the same guard as `ThemeSheetTests`.
 */
class ThemeSheetTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

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

    @Test
    fun `level one shows the presets and no axis control`() {
        val level = code("ThemeSheet.kt")

        assertTrue("level one still draws the preset grid", level.contains("PresetCard("))

        val axes = mapOf(
            "a slider" to "Slider(",
            "the font-size stepper" to "FontSizeControl",
            "the typeface picker" to "TypefaceControl",
            "the spacing sliders" to "FineAxes",
            "the alignment picker" to "AlignmentControl",
            "the brightness slider" to "BrightnessControl",
            "the page colours" to "PageColourSection",
            "the page-turn picker" to "PageTurnControl",
        )
        for ((what, spelling) in axes) {
            assertTrue(
                "Level one draws $what — `$spelling` is in `ThemeSheet.kt`. `ebook-reader`:" +
                    " \"the six preset swatches are what is shown, with no axis control among" +
                    " them\". A reader who wants Paper must not scroll past nine sliders to" +
                    " find it.",
                !level.contains(spelling),
            )
        }
    }

    @Test
    fun `one action of equal prominence opens the axes`() {
        val level = code("ThemeSheet.kt")

        assertTrue(
            "Level one has no action that opens the axes. `ebook-reader` gives it \"equal" +
                " prominence to the grid\".",
            level.contains("onClick = onCustomise"),
        )
        assertTrue(
            "The action that opens the axes is not full width, so it does not read as the" +
                " grid's peer. `ebook-reader` gives it \"equal prominence to the grid\" — a" +
                " footnote under six cards is not that.",
            level.contains("Button(\n            onClick = onCustomise,\n" +
                "            modifier = Modifier.fillMaxWidth(),"),
        )
    }

    @Test
    fun `level two is a destination with its own bar and close affordance, not a nested sheet`() {
        val level = code("ThemeAxesScreen.kt")

        assertTrue(
            "Level two is not a destination. `design.md`: Material never mentions a nested or" +
                " stacked bottom sheet, and predictive back is a component-level contract —" +
                " two stacked modal sheets give the gesture two competing dismiss targets and" +
                " no correct preview. A destination has one.",
            !level.contains("ModalBottomSheet("),
        )
        assertTrue(
            "Level two has no top app bar of its own. `design.md`: \"a destination —" +
                " full-screen, its own top app bar, a close affordance\".",
            level.contains("TopAppBar("),
        )
        assertTrue(
            "Level two has no close affordance in its bar.",
            level.contains("navigationIcon = {") && level.contains("IconButton(onClick = onClose)"),
        )
        assertTrue(
            "Level two does not answer the system back gesture. That is the other half of" +
                " being a destination: one dismiss target rather than two.",
            level.contains("BackHandler(onBack = onClose)"),
        )
    }

    @Test
    fun `level two draws the specimen, every axis, and the reset`() {
        val level = code("ThemeAxesScreen.kt")

        val expected = mapOf(
            "the live specimen of the publication's own text" to "ThemePreview(",
            "the font-size stepper" to "FontSizeControl(",
            "the typeface picker" to "TypefaceControl(",
            "the spacing sliders" to "FineAxes(",
            "the alignment picker" to "AlignmentControl(",
            "the brightness slider" to "BrightnessControl(",
            "the page colours" to "PageColourSection(",
            "the notice for axes Original cannot honour" to "PublisherStylesNotice(",
            "the reset" to "ResetToPreset(",
        )
        for ((what, spelling) in expected) {
            assertTrue(
                "Level two is missing $what — `$spelling` is not in `ThemeAxesScreen.kt`." +
                    " `ebook-reader` requires \"the axes offered are exactly those in" +
                    " `reading-themes`, with none added and none dropped\", over \"a specimen" +
                    " of the publication's own text in the active theme, which updates as an" +
                    " axis changes\".",
                level.contains(spelling),
            )
        }
    }

    @Test
    fun `every slider states its value beside it, once`() {
        val level = code("ThemeAxesScreen.kt")

        assertTrue(
            "The sliders do not state their value beside them. `reading-themes`: \"its" +
                " current value is stated beside it in the reader's own language and units," +
                " and updates as the control moves\".",
            level.contains("text = spoken,"),
        )
        assertTrue(
            "The visible value is not cleared of semantics. `reading-themes` requires the" +
                " value to be available \"as part of the control rather than as a separate" +
                " unlabelled element\" — a label left visible to TalkBack lands between the" +
                " axis's name and its slider and reads a bare number, which is exactly the" +
                " separate element the requirement names.",
            level.contains("Modifier.clearAndSetSemantics {}"),
        )
        assertTrue(
            "The mid-default axes do not use the centred track. `design.md`:" +
                " `SliderDefaults.CenteredTrack` \"for character spacing, word spacing and" +
                " margins, whose defaults sit mid-range\".",
            level.contains("SliderDefaults.CenteredTrack(state)"),
        )
    }

    @Test
    fun `the reset names its preset, is absent when unmodified, and is low-emphasis`() {
        val level = code("ThemeAxesScreen.kt")

        assertTrue(
            "The reset is not gated on the preset being modified. `reading-themes`: the" +
                " action is \"absent rather than present and doing nothing, because a control" +
                " that never changes anything teaches a reader to distrust the ones that" +
                " do\".",
            level.contains("if (!theme.isModified) return"),
        )
        assertTrue(
            "The reset does not name the preset it restores. `reading-themes`: \"the reader" +
                " who modified Calm is offered Calm back, not an unnamed default\".",
            level.contains("R.string.theme_restore_named"),
        )
        assertTrue(
            "The reset is not a low-emphasis text button. `design.md`: **Material has nothing" +
                " to say about reset-to-defaults** — no component, no pattern — and the" +
                " Dialogs page's discard-unsaved-changes prompt is about abandoning edits" +
                " rather than restoring defaults.",
            level.contains("TextButton(onClick = onRestore"),
        )
        assertTrue(
            "The reset asks for confirmation. It should not: it is immediately reversible by" +
                " picking the preset again, and a dialogue over an undoable change is one a" +
                " reader learns to dismiss unread.",
            !level.contains("AlertDialog"),
        )
    }

    @Test
    fun `Bold is a list item with a supporting line and a trailing switch`() {
        val level = code("ThemeAxesScreen.kt")

        assertTrue(
            "The switch axes are not `ListItem`s. `design.md`: `ListItem(content =," +
                " supportingContent =, trailingContent = Switch)`, with `toggleable` on the" +
                " item — Material authorises the supporting line on a list item, and the" +
                " Switch page requires only an inline label.",
            level.contains("supportingContent = { Text(supporting) }"),
        )
        assertTrue(
            "The item is not the toggleable. A switch on its own is an unnamed node: its" +
                " label is a sibling, and a screen reader landing on it hears a bare on/off.",
            level.contains(".toggleable(value = checked, role = Role.Switch"),
        )
        assertTrue(
            "The switch still claims the gesture. `onCheckedChange = null` is what stops the" +
                " item and the switch from both taking it.",
            level.contains("Switch(checked = checked, onCheckedChange = null)"),
        )
    }

    @Test
    fun `the sheet state is the one Material replaced the deprecated factory with`() {
        val level = code("ThemeSheet.kt")

        assertTrue(
            "Level one still calls the deprecated `rememberModalBottomSheetState`. It carries" +
                " an exact `replaceWith` pointing at `rememberBottomSheetState(initialValue," +
                " enabledValues, confirmValueChange)`.",
            !level.contains("rememberModalBottomSheetState"),
        )
        assertTrue(
            "Level one does not use `rememberBottomSheetState`.",
            level.contains("rememberBottomSheetState("),
        )
        assertTrue(
            "`enabledValues` is not stated. Since alpha21 the `PartiallyExpanded` anchor is" +
                " no longer removed for you, so a sheet that says nothing gets all three by" +
                " accident rather than by decision.",
            level.contains("enabledValues = setOf("),
        )
    }

    @Test
    fun `the header row toggles the sheet's height, which Material requires and does not offer`() {
        val level = code("ThemeSheet.kt")

        assertTrue(
            "Level one's header does not toggle the sheet's height. Material says" +
                " \"selecting the drag handle should toggle through preset heights\" and" +
                " specifies a Space/Enter contract for it — and `BottomSheetDefaults" +
                ".DragHandle` has no `onClick`. A multi-height sheet owes the hand-built" +
                " alternative Material explicitly requires.",
            level.contains("sheetState.partialExpand()") && level.contains("sheetState.expand()"),
        )
        assertTrue(
            "The height toggle has no button role or state, so it has no Space/Enter" +
                " contract for a screen reader.",
            level.contains("role = Role.Button") && level.contains("stateDescription = action"),
        )
    }

    @Test
    fun `the reset leaves the destination up, so the specimen shows the change`() {
        val level = code("ThemeAxesScreen.kt")
        val reset = level.substringAfter("private fun ResetToPreset(").substringBefore("\n}")

        assertTrue(
            "The reset closes the destination. `reading-themes` asks for the change to be" +
                " \"visible behind the sheet without the sheet being dismissed\" — and the" +
                " specimen at the top of this screen is the nearer proof, because it repaints" +
                " as the values go back.",
            !reset.contains("onClose"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
    }
}
