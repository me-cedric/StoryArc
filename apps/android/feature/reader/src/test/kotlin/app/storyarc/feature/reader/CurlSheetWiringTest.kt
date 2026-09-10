package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the sheet the shader turns comes out of the page cache, in both directions.
 *
 * `CurlTurnTest` asserts the mapping — which sheet turns at a negative progress, and which
 * page lies under it. It cannot assert where the bitmaps came from, and that is the part
 * with a cost: the curl is handed two decoded pages per frame, and a `previous` fetched by
 * decoding rather than by asking the cache would decode a page on the first backwards
 * pixel of every drag. `page-transitions` allows the curl "only where the pages either
 * side are already decoded", so this reads the call and names the accessor.
 *
 * **It asserts a call is written, not that a decode did not happen.** The accessor it names
 * is the reader's cache read — `ReaderViewModel.image` returns what the prefetch window
 * holds and null otherwise, and null is what makes the first page refuse to turn back. A
 * profiler is what would prove the frame cost; this is what fails when someone reaches
 * past the cache.
 */
class CurlSheetWiringTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val readerScreen: String by lazy {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt")
        if (!file.isFile) error("ReaderScreen.kt is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    @Test
    fun `the page behind is null at the first page, not the first page itself`() {
        // `modelIndex` answers 0 for a display position that has no slot, so a bare
        // `current - 1` hands the shader page 0 as page 0's own previous -- and the first
        // page turns backwards onto itself, which is worse than not turning.
        assertTrue(
            "The guard on the first page is gone: `modelIndex(-1)` is 0, so `previous` is" +
                " the page in view and the first page turns back onto itself.",
            readerScreen.contains("takeIf { paging.current > 0 }"),
        )
    }

    @Test
    fun `each of the three sheets is a cache read at a display position`() {
        val reads = listOf(
            "page = viewModel.image(modelIndex(paging.current))",
            "beneath = viewModel.image(modelIndex(paging.current + 1))",
            "previous = viewModel.image(modelIndex(paging.current - 1))\n" +
                "                        .takeIf { paging.current > 0 }",
        )

        for (read in reads) {
            assertTrue(
                "The curl no longer reads `$read`. If the sheet is fetched some other way," +
                    " the curl decodes a page mid-drag.",
                readerScreen.contains(read),
            )
        }
    }

    @Test
    fun `a completed turn moves to a display position in each direction`() {
        assertTrue(
            "A completed forward turn no longer turns the page.",
            readerScreen.contains("onTurned = { turn(paging.current + 1) }"),
        )
        assertTrue(
            "A completed backwards turn no longer turns the page back — which is the whole" +
                " of what a reader reported as a curl that works in one direction.",
            readerScreen.contains("onTurnedBack = { turn(paging.current - 1) }"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
