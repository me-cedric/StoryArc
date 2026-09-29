package app.storyarc.feature.reader

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.pager.PagerState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * A swipe or a scroll past the last page reaches the end screen.
 *
 * `comic-reader`: "a swipe or a scroll past the last page reaches the end screen". Before
 * this, only `turn` (a tap, a key, the slider) ever set `hasReachedEnd`; `HorizontalPager`
 * and `LazyColumn`/`LazyRow` had nowhere further to go and simply resisted at the last page.
 *
 * **Why it reads the source text.** The rule lives inside a live pager and a live scroll
 * state, both of which need a device; this module has no instrumented test source set.
 * `ReaderSystemChromeTest` is the same choice made for the same reason and carries the same
 * warning: this is a tripwire, not a proof. It says the wiring is there; it never says a
 * finger reached the end screen.
 */
class EndSlotTest {

    private val code: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SCREEN_SOURCE)
        if (!file.isFile) {
            error("$SCREEN_SOURCE is not under ${module.absolutePath} — has the screen moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    private val pagingCode: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File) ?: error(MODULE_DIRECTORY)
        File(module, PAGING_SOURCE).readText()
    }

    @Test
    fun `the pager gets one slot past the last page`() {
        assertTrue(
            "HorizontalPager no longer has an extra slot to swipe into. Without it a swipe" +
                " past the last page simply resists, the way it resists at the first.",
            pagingCode.contains("pageCount = { count + 1 }"),
        )
    }

    @Test
    fun `the scroll lists get one slot past the last page`() {
        assertTrue(
            "The vertical scroll no longer has an extra slot past the last page.",
            code.contains("items(slotCount + 1) { item ->"),
        )
    }

    @Test
    fun `reaching the extra slot opens the end screen`() {
        assertTrue(
            "Reaching the extra slot no longer opens the end screen. `comic-reader`: \"a" +
                " swipe or a scroll past the last page reaches the end screen\".",
            code.contains("if (position == endSlot) {"),
        )
        assertTrue(
            code.contains("hasReachedEnd = true"),
        )
    }

    @Test
    fun `going back off the end screen snaps off the extra slot`() {
        assertTrue(
            "Going back from the end screen no longer snaps off the extra slot. Left there," +
                " the reader would find a blank page instead of the last one they read.",
            code.contains("if (paging.current == endSlot) {"),
        )
    }

    @Test
    fun `left-to-right puts the end slot after the last page`() {
        assertEquals(5, endSlotPosition(slotCount = 5, isRightToLeft = false))
    }

    @Test
    fun `right-to-left puts the end slot before the last page, not after page one`() {
        // Under right-to-left the last page is display position 0, so the slot past it
        // is -1. At `slotCount` it sat past page one, and a swipe back opened the end.
        assertEquals(-1, endSlotPosition(slotCount = 5, isRightToLeft = true))
    }

    @Test
    fun `a pager with the end slot first reports it as the end slot's position`() {
        val atEnd = Paging.Paged(PagerState(currentPage = 0) { 6 }, lead = 1)
        assertEquals(endSlotPosition(slotCount = 5, isRightToLeft = true), atEnd.current)
        val onLastPage = Paging.Paged(PagerState(currentPage = 1) { 6 }, lead = 1)
        assertEquals(0, onLastPage.current)
    }

    @Test
    fun `a scroll with the end slot first reports it as the end slot's position`() {
        val atEnd = Paging.Scrolled(LazyListState(firstVisibleItemIndex = 0), lead = 1)
        assertEquals(-1, atEnd.current)
        val onPageOne = Paging.Scrolled(LazyListState(firstVisibleItemIndex = 5), lead = 1)
        assertEquals(4, onPageOne.current)
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        const val SCREEN_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt"
        const val PAGING_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/Paging.kt"
    }
}
