package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Task 15.8: the comic pager, the horizontal scroll and the thumbnail strip must lay
 * pages out left-to-right on screen, whatever the interface language's own direction.
 *
 * `local-library`: a reading-order step is "one step right on screen" for the next page in
 * every case this app supports, and the Android manifest sets `supportsRtl="true"`, so an
 * Arabic or Hebrew interface language mirrors every `HorizontalPager` and `LazyRow` in the
 * app by default -- paging a left-to-right comic backwards.
 *
 * **Why it reads the source text.** This module has no Bitmap support off-device (see
 * `ReaderModelTests`' own note on why `comic-reader`'s decode path is instrumented, not
 * unit-tested), so a `HorizontalPager` fed real pages cannot be composed here either.
 * `ThumbnailBrowserTest` already answers this module's Compose behaviour the same way: a
 * tripwire on the source, not a render.
 */
class ReaderPagesStayLtrTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    /** A file's code, with its prose removed. See `ThumbnailBrowserTest.code` for why. */
    private fun code(relative: String): String {
        val file = File(module, relative)
        if (!file.isFile) {
            error("$relative is not under ${module.absolutePath} — has it moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        return withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    /**
     * Whether [container] is the thing `Ltr {` wraps: with only whitespace stripped, the text
     * immediately before [container] ends in `Ltr {`. Adjacency, not a brace count across the
     * whole file -- a wrap on some *other*, earlier branch is still "the last `Ltr {` seen",
     * which a looser scan would count as covering every branch after it.
     */
    private fun isWrapped(source: String, container: String): Boolean {
        val at = source.indexOf(container)
        assertTrue("$container is no longer in the source.", at >= 0)
        return source.substring(0, at).trimEnd().endsWith("Ltr {")
    }

    @Test
    fun `the paged pager is wrapped in Ltr`() {
        assertTrue(
            "HorizontalPager is not wrapped in Ltr. An RTL interface language mirrors it," +
                " paging a left-to-right comic backwards.",
            isWrapped(code(SCREEN_SOURCE), "HorizontalPager(state = paging.state"),
        )
    }

    @Test
    fun `the scrolled horizontal row is wrapped in Ltr`() {
        assertTrue(
            "The horizontal LazyRow (Paging.Scrolled, non-vertical) is not wrapped in Ltr.",
            isWrapped(code(SCREEN_SOURCE), "LazyRow(state = paging.state"),
        )
    }

    @Test
    fun `the thumbnail carousel is wrapped in Ltr`() {
        assertTrue(
            "ThumbnailStrip's HorizontalPager is not wrapped in Ltr.",
            isWrapped(code(STRIP_SOURCE), "HorizontalPager("),
        )
    }

    @Test
    fun `Ltr itself pins LayoutDirection to Ltr`() {
        val source = code(LTR_SOURCE)
        assertTrue(
            "Ltr no longer pins LocalLayoutDirection to LayoutDirection.Ltr.",
            source.contains("LocalLayoutDirection provides LayoutDirection.Ltr"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val SCREEN_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt"
        const val STRIP_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ThumbnailStrip.kt"
        const val LTR_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/LtrLayout.kt"
    }
}
