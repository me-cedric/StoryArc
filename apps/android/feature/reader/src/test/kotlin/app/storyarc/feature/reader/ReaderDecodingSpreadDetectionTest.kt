package app.storyarc.feature.reader

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a decoded page's own shape is judged by [app.storyarc.core.format.PageDecoder.isSpread]'s
 * margin, not by a bare `width > height` with no tolerance.
 *
 * D27: `PageDecoder.isSpread` had no production caller on either platform -- the inline rule in
 * `ReaderDecoding.kt` ran instead, with no margin, so a page one percent wider than tall from a
 * slight scan skew counted as a spread. The decision keeps the 1.2 margin "materially wider"
 * implies and calls `isSpread` at both `noteDecoded` sites. iOS's
 * `ReaderModelSpreadDetectionTests` asserts the same two cases against the real function, which
 * this module's unit tests cannot: `Bitmap` is a framework stub off-device, and `decode(_:_:)`
 * is a private suspend extension reached only through a full `ReaderViewModel`.
 *
 * The assertion is a source guard rather than a behaviour test, for the same reason
 * `ReaderFailureSaysNothingInternalTest` in this module is one.
 */
class ReaderDecodingSpreadDetectionTest {
    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own sources and will" +
                    " not go looking for them elsewhere -- run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, DECODING_FILE)
        if (!file.isFile) error("$DECODING_FILE is not under ${module.absolutePath} -- has it moved?")
        file.readText()
    }

    @Test
    fun `the wide-page decision calls PageDecoder isSpread`() {
        assertTrue(
            "$DECODING_FILE no longer calls PageDecoder.isSpread(. A bare width-over-height" +
                " comparison with no margin reads a page one percent wider than tall, from a" +
                " slight scan skew, as a spread -- the defect D27 fixed.",
            source.contains("PageDecoder.isSpread("),
        )
    }

    @Test
    fun `no bare width-over-height comparison decides a spread instead`() {
        assertFalse(
            "$DECODING_FILE compares width and height directly to decide a spread, bypassing" +
                " PageDecoder.isSpread's 1.2 margin.",
            source.lines().any { it.trim().startsWith("if (bitmap.width > bitmap.height)") },
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val DECODING_FILE = "src/main/kotlin/app/storyarc/feature/reader/ReaderDecoding.kt"
    }
}
