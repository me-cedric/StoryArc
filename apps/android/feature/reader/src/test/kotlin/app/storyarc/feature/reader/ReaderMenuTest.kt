package app.storyarc.feature.reader

import app.storyarc.core.model.ReaderMenuEntry
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the declutter did not remove a capability.
 *
 * `comic-reader`, *Everything else is in the menu, and labelled*:
 *
 * > **THEN** it offers the table of contents, bookmarks, search within the publication,
 * > reading themes and reader settings, each named in words rather than by icon alone
 * > **AND** every control that was reachable from the reader before this change is
 * > reachable from here in one action
 *
 * **This is the test the change needed most.** Cutting eleven controls to two is easy; the
 * hard part is that nothing is lost doing it, and nothing in a compiler notices a row that
 * quietly stopped being drawn. `ReaderChromeTest` proves the chrome is small. This proves the
 * smallness cost nothing.
 *
 * Two halves, and they fail for different reasons:
 *
 * - **Labelled.** Every `ReaderMenuEntry` has a row in the menu's source and a name in this
 *   module's own `strings.xml`, in all four supported languages. Android's `lint` catches a
 *   missing translation of a key it can see; it cannot see that a *row* was dropped.
 * - **Reachable.** Each control the chrome used to draw is named somewhere in the menu's own
 *   source.
 *
 * **The second half reads source text, and it is a tripwire rather than a proof.** It says
 * the destination is spelled somewhere in the menu; it never says a row appeared or that
 * tapping it arrived. `ReaderChromeTest` beside it carries the same warning for the same
 * reason: nothing in this repository runs an instrumented test on this module.
 */
class ReaderMenuTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    /**
     * The menu's code, with its prose removed, as one string.
     *
     * Two files rather than one: the rows and the settings controls. The menu is what they add
     * up to, so the guard reads both — a capability moved between them is still in the menu,
     * and a capability deleted from both is not.
     */
    private val code: String by lazy {
        MENU_SOURCES.joinToString("\n") { relative ->
            val file = File(module, relative)
            if (!file.isFile) {
                error("$relative is not under ${module.absolutePath} — has the menu moved?")
            }
            val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
                .replace(file.readText(), "")
            withoutBlocks.lineSequence().joinToString("\n") { line ->
                val comment = line.indexOf("//")
                if (comment >= 0) line.substring(0, comment) else line
            }
        }
    }

    /**
     * What the chrome could reach before this change, and the spelling that reaches it now.
     *
     * The floor is 2 where the entry is a composable of the menu's own: one occurrence is its
     * declaration, so a row deleted from `ReaderSettingsRows` while its body is left behind
     * would still be spelled once. Requiring two is what makes deleting the *use* fail.
     */
    private val capabilities = listOf(
        Triple("the thumbnail browser", "ThumbnailStrip(", 1),
        Triple("the PDF mark list", "PdfTextTab.MARKS", 1),
        Triple("search inside the publication", "PdfTextTab.SEARCH", 1),
        Triple("the image adjustments", "onAdjust", 2),
        Triple("the chapter neighbours", "ChapterRows(", 2),
        Triple("the page slider", "PageSlider(", 2),
        Triple("the page-transition choice", "TransitionRow(", 2),
        Triple("the page-fit choice", "FitRow(", 2),
        Triple("the reading-direction choice", "DirectionRow(", 2),
        Triple("the spread offset", "reader_spreads_offset", 1),
        Triple("the rotation lock", "reader_orientation_lock", 1),
        Triple("the continuous-scroll separator", "reader_separator", 1),
        Triple("the skipped-page count", "reader_skipped", 1),
    )

    @Test
    fun `the menu reaches everything the eleven icons did`() {
        for ((what, spelling, floor) in capabilities) {
            val found = code.split(spelling).size - 1
            assertTrue(
                "The reader's menu no longer reaches $what — `$spelling` appears $found" +
                    " time(s) in its source and $floor was the floor. `comic-reader` requires" +
                    " every control that was reachable from the reader before the declutter to" +
                    " stay reachable from the menu in one action. Cutting eleven controls to" +
                    " two is only correct if nothing was lost doing it.",
                found >= floor,
            )
        }
    }

    @Test
    fun `every menu row is named in words, in all four languages`() {
        for (entry in ReaderMenuEntry.entries) {
            val name = "reader_menu_" + entry.name.lowercase()

            assertTrue(
                "The reader's menu does not draw a row for ${entry.name}. `comic-reader`" +
                    " requires the menu to offer the contents, bookmarks, search, themes and" +
                    " settings — the five `ReaderMenuEntry` names — each of them labelled.",
                code.contains("ReaderMenuEntry.${entry.name}"),
            )

            for (folder in LANGUAGES) {
                val strings = File(module, "src/main/res/$folder/strings.xml")
                if (!strings.isFile) {
                    error("$folder/strings.xml is missing from ${module.absolutePath}.")
                }
                assertTrue(
                    "$folder/strings.xml has no `$name`. `localization` requires a build that" +
                        " fails \"if any supported language is missing a key that English" +
                        " defines\", and a row whose name is missing renders as the key.",
                    strings.readText().contains("name=\"$name\""),
                )
            }
        }
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        val MENU_SOURCES = listOf(
            "src/main/kotlin/app/storyarc/feature/reader/ReaderMenuSheet.kt",
            "src/main/kotlin/app/storyarc/feature/reader/ReaderControls.kt",
        )

        /** The four `localization` names. English is the one every other falls back to. */
        val LANGUAGES = listOf("values", "values-de", "values-es", "values-fr")
    }
}
