package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That Curl mode names a page still loading or that could not be decoded, rather than
 * leaving a bare matte.
 *
 * `publication-formats` "Page not yet available": "a progress indicator appears only
 * after 400 ms", and an undecodable page shows "a placeholder naming the codec". Before
 * this, `CurledPages`'s `Canvas` returned before drawing anything at all — not even the
 * matte — the moment the current page had not decoded, because every early return sat
 * ahead of the one `drawRect` call. `SinglePage` already drew both cases; the curl drew
 * neither.
 *
 * Source-read, the same choice `CurlOverImagePagesTest` and `CurlSheetWiringTest` make
 * for the same reason: the honest test is a screenshot on a device, and this is a
 * tripwire, not a proof.
 */
class CurlUnavailablePageTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val curledPages: String by lazy {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/CurledPages.kt")
        if (!file.isFile) error("CurledPages.kt is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    @Test
    fun `the matte draws before any early return, not after`() {
        val matte = curledPages.indexOf("drawRect(color = matte, size = size)")
        val versionGuard = curledPages.indexOf("if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return@Canvas")
        assertTrue("CurledPages.kt no longer draws the matte in its Canvas block.", matte >= 0)
        assertTrue(
            "CurledPages.kt no longer has the version guard this test orders the matte against.",
            versionGuard >= 0,
        )
        assertTrue(
            "The matte draws after the version guard, not before it. A page that has not" +
                " decoded returns out of the Canvas at that guard (or the ones after it), so" +
                " a matte drawn later is a matte a reader on a loading page never sees —" +
                " task 8.15's whole defect.",
            matte < versionGuard,
        )
    }

    @Test
    fun `a page still loading or that could not be decoded is named over the matte`() {
        assertTrue(
            "CurledPages no longer checks whether the current page has decoded.",
            curledPages.contains("CurlTurn.sheets(progress.value, page, beneath, previous).turning == null"),
        )
        assertTrue(
            "An undecodable page no longer shows the codec-naming Message.",
            curledPages.contains("if (isUnavailable) {") && curledPages.contains("Message("),
        )
        assertTrue(
            "A page still loading no longer shows the delayed progress indicator.",
            curledPages.contains("DelayedProgressIndicator()"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
