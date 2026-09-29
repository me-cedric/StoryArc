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

    private fun sourceOf(name: String): String {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/$name")
        if (!file.isFile) error("$name is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    private val readerScreen: String by lazy { sourceOf("ReaderScreen.kt") }
    private val paging: String by lazy { sourceOf("Paging.kt") }
    private val curledPages: String by lazy { sourceOf("CurledPages.kt") }

    /**
     * Just the arguments of the one call that builds the curl.
     *
     * Bracket-matched rather than a fixed line count, so a comment added above the call
     * cannot shift the window off the arguments it exists to check. The file holds other
     * calls that repeat some of the same argument text — `matte = matte,` and
     * `adjustments = adjustments,` both appear on an ordinary page too — so a check
     * against the whole file would pass with the curl's own copy missing.
     */
    private fun curlBuilder(): String {
        val open = readerScreen.indexOf("CurledPages(").let {
            check(it >= 0) { "ReaderScreen.kt no longer builds a CurledPages(...) — has it moved?" }
            readerScreen.indexOf('(', it)
        }
        var depth = 1
        var i = open + 1
        while (depth > 0) {
            when (readerScreen[i]) {
                '(' -> depth++
                ')' -> depth--
            }
            i++
        }
        return readerScreen.substring(open, i)
    }

    @Test
    fun `the page behind is null past either end of the publication, not that end's own page`() {
        // `modelIndex` answers 0 for a display position that has no slot, so a bare
        // `current - 1` hands the shader page 0 as page 0's own previous -- and the first
        // page turns backwards onto itself, which is worse than not turning. Task 8.14
        // moved the guard from a raw `paging.current > 0` check into `adjacentDisplayIndex`,
        // because that same guard has to run in reading-order space for right-to-left.
        assertTrue(
            "adjacentDisplayIndex no longer bounds its candidate to the publication's slots" +
                " — the guard that stops the first page turning back onto itself.",
            paging.contains("candidate.takeIf { it in 0 until slotCount }"),
        )
    }

    @Test
    fun `each of the three sheets is a cache read at a display position, trimmed`() {
        val builder = curlBuilder()
        val reads = listOf(
            "page = curlPage(paging.current)",
            "beneath = curlSheet(adjacentDisplayIndex(paging.current, 1, slotCount, isRightToLeft))",
            "previous = curlSheet(adjacentDisplayIndex(paging.current, -1, slotCount, isRightToLeft))",
        )

        for (read in reads) {
            assertTrue(
                "The curl no longer reads `$read`. If the sheet is fetched some other way," +
                    " the curl decodes a page mid-drag.",
                builder.contains(read),
            )
        }

        // `curlPage` is the accessor `viewModel.image` moved into: still a cache read, now
        // with the series' border trim baked in (task 8.1, `comic-reader` "Persisting
        // adjustments").
        assertTrue(
            "curlPage no longer reads the reader's decoded-page cache.",
            readerScreen.contains("val raw = viewModel.image(index) ?: return null"),
        )
        assertTrue(
            "curlPage no longer bakes the series' border trim into the sheet it hands the curl.",
            readerScreen.contains("raw.cropped(trims)"),
        )
        // Task 8.4: a neighbour that has not decoded is a placeholder, not the outgoing page.
        assertTrue(
            "curlSheet no longer falls back to a placeholder for a neighbour still decoding.",
            readerScreen.contains("CurlPlaceholder.sheet(display, { curlPage(it) }) {") &&
                readerScreen.contains("rememberCurlPlaceholder(PagePlaceholder.ratio(modelIndex(it),"),
        )
    }

    @Test
    fun `a completed turn moves to a reading-order position in each direction`() {
        val builder = curlBuilder()
        // Not a raw `paging.current + 1`: right-to-left reverses the display order, so a
        // completed *forward* turn (task 8.14) has to move by a reading-order step, which
        // is -1 there.
        assertTrue(
            "A completed forward turn no longer turns the page by a reading-order step.",
            builder.contains("onTurned = { turn(paging.current + readingOrderStep(1, isRightToLeft)) }"),
        )
        assertTrue(
            "A completed backwards turn no longer turns the page back by a reading-order" +
                " step — which is the whole of what a reader reported as a curl that works" +
                " in one direction.",
            builder.contains(
                "onTurnedBack = { turn(paging.current + readingOrderStep(-1, isRightToLeft)) }",
            ),
        )
    }

    @Test
    fun `the curl is handed the series' colour and sharpness adjustments`() {
        assertTrue(
            "The curl no longer draws the series' brightness, contrast, inversion, " +
                "greyscale and sharpness. `comic-reader` \"Persisting adjustments\" applies " +
                "to every container.",
            curlBuilder().contains("adjustments = adjustments,"),
        )
    }

    @Test
    fun `the curl is handed whether the current page could not be decoded, and its codec`() {
        // task 8.15: a curl over a page that has not decoded showed a bare matte. The
        // reason and the codec are the same two facts `SinglePage` already reads for the
        // stitched and paged bodies.
        val builder = curlBuilder()
        assertTrue(
            "The curl no longer reads whether the current page is unavailable.",
            builder.contains("isUnavailable = viewModel.isUnavailable(modelIndex(paging.current)),"),
        )
        assertTrue(
            "The curl no longer reads the current page's codec name.",
            builder.contains("codecName = viewModel.codecName(modelIndex(paging.current)),"),
        )
    }

    @Test
    fun `the curl draws the series' colour and sharpness over its own sheet`() {
        // Task 8.1: handing the curl `adjustments` does nothing unless its draw uses them.
        assertTrue(
            "The curl's shader rect no longer draws through the series' colour filter.",
            curledPages.contains("drawRect(brush = ShaderBrush(shader), size = size, colorFilter = colours)"),
        )
        assertTrue(
            "The curl's layer no longer carries the series' sharpening effect.",
            curledPages.contains(".graphicsLayer { renderEffect = sharpen }"),
        )
    }

    @Test
    fun `the curl parses its shader once, not once a frame`() {
        // Task 8.7: `RuntimeShader(source)` parses the AGSL program. The draw block runs
        // once a frame, so the one construction has to sit behind a `remember`.
        val constructions = sourceOf("PageCurl.kt").lines()
            .filter { it.contains("RuntimeShader(") && !it.trimStart().startsWith("*") }
        assertTrue(
            "PageCurl.kt constructs a RuntimeShader somewhere other than `newShader`: $constructions",
            constructions.map(String::trim) == listOf("fun newShader(): RuntimeShader = RuntimeShader(source)"),
        )
        assertTrue(
            "CurledPages no longer keeps its shader in a `remember` block.",
            Regex("""remember \{\s*if \([^)]*\) PageCurl\.newShader\(\)""").containsMatchIn(curledPages),
        )
        assertTrue(
            "CurledPages calls `PageCurl.newShader()` more than once.",
            curledPages.split("PageCurl.newShader()").size == 2,
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
