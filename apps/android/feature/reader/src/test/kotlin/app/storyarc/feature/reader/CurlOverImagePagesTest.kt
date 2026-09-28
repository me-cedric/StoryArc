package app.storyarc.feature.reader

import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.File

/**
 * That a curl over a comic page turns the page that was already decoded, rather than a
 * re-raster of it.
 *
 * `comic-reader`, *Curl over image pages*:
 *
 * > **WHEN** a curl runs over a comic page
 * > **THEN** it uses the already-decoded page directly rather than a re-raster, because the
 * > page is an image before the turn begins
 *
 * **One claim, and this class asserts it.** `CurlSheetWiringTest` already asserts that every
 * sheet the curl draws is a cache read at a display position, which is the stricter form of
 * the same requirement — this class only adds the compiler cannot make on its own: nothing
 * on the curl's path turns a composition back into a picture. Handing `CurledPages` a
 * captured layer is legal Kotlin — a `GraphicsLayer` yields an `ImageBitmap` like any other —
 * so a screen that re-rendered the page would pass every other gate in this repository.
 *
 * **Why it reads the source text.** The honest test measures the frame a turn costs on a
 * device, and `FrameProbe` is that instrument; no gate in this repository runs it.
 * `ReaderChromeTest` and `ReaderGestureTest` are the same choice made for the same reason and
 * carry the same warning: this is a tripwire, not a proof. `CurlOverImagePagesTests` is the
 * iOS half.
 */
class CurlOverImagePagesTest {

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
     * Comments are stripped first: this codebase explains itself at length, and both
     * "re-raster" and the capture APIs below are words it uses in its own paragraphs.
     */
    private fun code(relative: String): String {
        val file = File(module, relative)
        if (!file.isFile) {
            error("$relative is not under ${module.absolutePath} — has the curl moved?")
        }
        val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
            .replace(file.readText(), "")
        return withoutBlocks.lineSequence().joinToString("\n") { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }
    }

    /**
     * The absence that the positive claim above cannot cover.
     *
     * Nothing here re-renders a composition. Each of these yields an image the curl's
     * parameters would accept, so any of them would satisfy the types and fail the
     * requirement.
     */
    @Test
    fun `nothing on the curl's path turns a composition back into a picture`() {
        for (relative in CURL_PATH) {
            val code = code(relative)
            for (rasteriser in RASTERISERS) {
                assertFalse(
                    "$relative reaches for `$rasteriser`. `comic-reader` requires the curl to" +
                        " take \"the already-decoded page directly rather than a re-raster\":" +
                        " the page is a `Bitmap` before the turn begins, and rendering the" +
                        " composition into a second one costs a full-page raster on the frame" +
                        " the finger lands.",
                    code.contains(rasteriser),
                )
            }
        }
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        const val SCREEN_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderScreen.kt"

        val CURL_PATH = listOf(
            SCREEN_SOURCE,
            "src/main/kotlin/app/storyarc/feature/reader/CurledPages.kt",
        )

        val RASTERISERS = listOf(
            "rememberGraphicsLayer",
            "drawToBitmap",
            "captureToImage",
            "PixelCopy",
        )
    }
}
