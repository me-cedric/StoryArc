package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That revealed chrome is two controls, and that neither of them is a fact about the page.
 *
 * `comic-reader`, *Revealing controls*:
 *
 * > **THEN** exactly two controls fade in over the page — one that closes the publication
 * > and one that opens the reader's menu — and the page does not reflow
 * > **AND** no title, page number, percentage or slider is drawn over the page
 *
 * **Why a count and not a list of forbidden controls.** The requirement explains itself: the
 * previous text named a top bar, a bottom bar and a page slider, and each of the eleven
 * controls between them was added on its own justification. Any wording other than a count
 * invites a twelfth. So this counts.
 *
 * **Why it reads the source text.** The honest test composes the chrome and counts what is
 * hittable, the way `ThemeSheetSemanticsTest` composes `StoryArcTheme` — and this module's
 * `androidTest` classes are run by nothing. `.github/workflows/android.yml` boots an emulator
 * for `:core:format:connectedDebugAndroidTest` and nothing else, while the unit gate runs on
 * every pull request. A guard that runs beats a better one that does not.
 *
 * It is a tripwire, not a proof: it says the chrome declares two buttons, never that two
 * buttons appeared. Its iOS counterpart is `ReaderChromeTests`, written for the same reason
 * and carrying the same warning. Delete both the day an instrumented run is a gate.
 */
class ReaderChromeTest {

    /**
     * The chrome's source, at the path the module's build script hands to the test JVM.
     *
     * Deliberately not discovered. Walking up from the working directory leaves the module:
     * this repository nests agent worktrees at `.claude/worktrees/<name>/`, so the walk climbs
     * out of the worktree under test and reads the parent checkout's copy — a guard passing or
     * failing on source that was never built.
     *
     * Comments are stripped before anything is counted. This codebase explains itself at
     * length, and every word below appears in a comment somewhere; a guard that counted
     * "IconButton" in a paragraph about icon buttons would be measuring the documentation.
     */
    private val code: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, CHROME_SOURCE)
        if (!file.isFile) {
            error("$CHROME_SOURCE is not under ${module.absolutePath} — has the chrome moved?")
        }
        // Block comments first, then line comments. KDoc is `/** … */`, and this file's own
        // prose names every one of the words below — a guard that found "percentage" in a
        // paragraph about percentages would be measuring the documentation.
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    @Test
    fun `the chrome declares exactly two controls`() {
        val buttons = Regex("""\bIconButton\(""").findAll(code).count()

        assertEquals(
            "The reader's chrome declares $buttons controls, not two. `comic-reader` requires" +
                " exactly two over the page: one that closes the publication and one that" +
                " opens the menu. A third belongs behind the menu, labelled in words — that" +
                " is the whole point of the count.",
            2,
            buttons,
        )
    }

    @Test
    fun `nothing that is a fact rather than an action is drawn over the page`() {
        // A slider is a control the count above would not catch, because it is not an
        // `IconButton`. The rest are not controls at all and no count reaches them, which is
        // why the requirement names them separately: they are the furniture that made the
        // chrome a fifth of a screen.
        val forbidden = mapOf(
            "a page slider" to "Slider(",
            "the page count" to "R.string.reader_page",
            "the page-transition and fit cluster" to "ReaderToolCluster",
            "the direction and rotation cluster" to "ReaderLayoutCluster",
            "the chapter row" to "ChapterRow",
            "the thumbnail strip" to "ThumbnailStrip",
            "the skipped-page notice" to "SkippedNotice",
        )

        for ((what, spelling) in forbidden) {
            assertTrue(
                "The reader's chrome draws $what — `$spelling` appears in it. `comic-reader`" +
                    " forbids a title, a page number, a percentage or a slider over the page," +
                    " because each of those is a fact the menu states better and none of them" +
                    " is an action. Move it onto a menu row.",
                !code.contains(spelling),
            )
        }
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val CHROME_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderChrome.kt"
    }
}
