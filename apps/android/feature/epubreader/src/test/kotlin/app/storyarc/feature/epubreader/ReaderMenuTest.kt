package app.storyarc.feature.epubreader

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
 * `:feature:reader`'s `ReaderMenuTest` is the same guard over the comic reader's menu, and
 * both check the same five `ReaderMenuEntry` names — that shared type is what keeps the two
 * menus from drifting, since the two modules do not depend on each other.
 *
 * **A tripwire, not a proof.** It says the destination is spelled somewhere in the menu; it
 * never says a row appeared or that tapping it arrived. `ReaderChromeTest` beside it carries
 * the same warning for the same reason.
 */
class ReaderMenuTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val code: String by lazy {
        val file = File(module, MENU_SOURCE)
        if (!file.isFile) {
            error("$MENU_SOURCE is not under ${module.absolutePath} — has the menu moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    /** What the five pills could reach before this change, and the spelling that reaches it. */
    private val capabilities = listOf(
        "the table of contents" to "ContentsTab.CONTENTS",
        "the bookmark list" to "ContentsTab.BOOKMARKS",
        "marking this position" to "onToggleBookmark",
        "search inside the book" to "ContentsTab.SEARCH",
        "highlights and notes" to "ContentsTab.ANNOTATIONS",
        "the reading themes" to "onOpenTheme",
        "starting read-aloud" to "onStartReadAloud",
        "stopping read-aloud" to "onStopReadAloud",
        "the progress line" to "epub_progress",
    )

    @Test
    fun `the menu reaches everything the five pills did`() {
        for ((what, spelling) in capabilities) {
            assertTrue(
                "The reflowable reader's menu no longer reaches $what — `$spelling` is not in" +
                    " its source. `comic-reader` requires every control that was reachable" +
                    " from the reader before the declutter to stay reachable from the menu in" +
                    " one action.",
                code.contains(spelling),
            )
        }
    }

    @Test
    fun `every menu row is named in words, in all four languages`() {
        for (entry in ReaderMenuEntry.entries) {
            val name = "reader_menu_" + entry.name.lowercase()

            assertTrue(
                "The reflowable reader's menu does not draw a row for ${entry.name}." +
                    " `comic-reader` requires the menu to offer the contents, bookmarks," +
                    " search, themes and settings — the five `ReaderMenuEntry` names.",
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
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val MENU_SOURCE =
            "src/main/kotlin/app/storyarc/feature/epubreader/EpubMenuSheet.kt"

        /** The four `localization` names. English is the one every other falls back to. */
        val LANGUAGES = listOf("values", "values-de", "values-es", "values-fr")
    }
}
