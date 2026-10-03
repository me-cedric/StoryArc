package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the thumbnail browser shows the whole publication, says where the reader is, and goes
 * where it is told.
 *
 * `comic-reader`, *Thumbnail browser*:
 *
 * > **THEN** every page is shown in a scrollable strip with the current page marked, and
 * > tapping one jumps to it
 *
 * Three claims, one per test below. The middle one carries a fourth that `native-experience`
 * adds and this strip honours: the mark is not colour alone, because a border is only colour.
 *
 * **Why it reads the source text.** The honest test composes the strip and taps a cell, the
 * way `ThemeSheetSemanticsTest` composes `StoryArcTheme`. This module has no instrumented
 * test source set, and the unit gate runs on every pull request. A guard that runs beats a
 * better one that does not. It is a tripwire, not a proof: it says the strip is built over
 * every page, never that a thumbnail appeared. `ThumbnailBrowserTests` is the iOS half.
 */
class ThumbnailBrowserTest {

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
     * A file's code, with its prose removed.
     *
     * Comments are stripped first: this codebase explains itself at length, and a guard that
     * found `isCurrent` in a paragraph about the current page would be measuring the
     * documentation.
     */
    private fun code(relative: String): String {
        val file = File(module, relative)
        if (!file.isFile) {
            error("$relative is not under ${module.absolutePath} — has the browser moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        return withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    @Test
    fun `the strip is built over every page of the publication`() {
        assertTrue(
            "The thumbnail strip is no longer built over `pageCount`. `comic-reader` requires" +
                " \"every page … shown in a scrollable strip\", and a strip built over a" +
                " window of the pages shows the reader a publication shorter than the one" +
                " they are holding.",
            code(STRIP_SOURCE).contains("items(pageCount)"),
        )
    }

    /**
     * Marked, and not by colour alone.
     *
     * `native-experience` forbids colour as the only signal, and a highlighted border is only
     * colour. The page number carries the mark as weight as well.
     */
    @Test
    fun `the page being read is marked, and not by colour alone`() {
        val strip = code(STRIP_SOURCE)
        assertTrue(
            "The thumbnail strip no longer marks the current page. `comic-reader` requires the" +
                " strip to be shown \"with the current page marked\" — without it a reader" +
                " forty pages in is handed three hundred identical cells.",
            strip.contains("isCurrent = index == currentIndex"),
        )
        assertTrue(
            "The current page is marked by colour alone. `native-experience` forbids colour as" +
                " the only signal, and the highlighted border is only colour. The page" +
                " number's weight is what carries the mark for a reader who cannot tell the" +
                " two borders apart.",
            strip.contains("fontWeight = if (isCurrent)"),
        )
        assertTrue(
            "The current page is not announced as selected. A mark drawn and not spoken is no" +
                " mark at all to a reader using TalkBack, and `comic-reader` asks for the page" +
                " to be marked rather than for it to be coloured.",
            strip.contains("selectable(selected = isCurrent"),
        )
    }

    @Test
    fun `tapping a thumbnail jumps to that page`() {
        assertTrue(
            "A thumbnail no longer reports the page it stands for. `comic-reader`: \"tapping" +
                " one jumps to it\".",
            code(STRIP_SOURCE).contains("onClick = { onSelect(index) }"),
        )

        val menu = code(MENU_SOURCE)
        assertTrue(
            "The menu no longer turns a tapped thumbnail into a jump. `comic-reader`:" +
                " \"tapping one jumps to it\" — and a jump rather than a turn, so the way back" +
                " from a mis-tap in a three-hundred-page strip is the one control `PageReturn`" +
                " already offers.",
            menu.contains("ThumbnailStrip(") && menu.contains("actions.onJump(index)"),
        )
    }

    @Test
    fun `the carousel mirrors for a right-to-left publication`() {
        assertTrue(
            "The carousel no longer converts between the publication's numbering and its own" +
                " display slot. `page-browser-carousel`: \"the carousel runs right to left," +
                " with page one at the right end\".",
            code(STRIP_SOURCE).contains("ChapterBrowser.displayIndex("),
        )
    }

    @Test
    fun `a drag on the slider centres the carousel, with no animation`() {
        assertTrue(
            "A slider drag no longer scrolls the carousel to the target page." +
                " `page-browser-carousel` §3: \"the slider's value sets the carousel's" +
                " centred page with no animation\" — `scrollToPage` jumps rather than" +
                " animating.",
            code(STRIP_SOURCE).contains("pagerState.scrollToPage(slot)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        const val STRIP_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ThumbnailStrip.kt"

        const val MENU_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderMenuSheet.kt"
    }
}
