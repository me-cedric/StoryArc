package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That `Page()` actually asks [app.storyarc.core.designsystem.navigation.hingeSpreadSplit]
 * and [app.storyarc.core.designsystem.navigation.hingeInset] for its layout, rather than
 * drawing the equal-weight split and the plain centring 19.5 replaced.
 *
 * `HingeAvoidanceTest` asserts the two functions' own arithmetic on a plain JVM, with no
 * window to fake. What it cannot see is whether `Page()` still calls them — a `Posture`
 * from a folded device is not a Robolectric shadow this repository has reached for
 * elsewhere, so this reads the call sites instead, in the manner of `CurlSheetWiringTest`.
 * **It asserts the call is written, not that a device folds correctly** — a real fold is
 * an instrumented or a manual check; this is what fails when someone reaches past the
 * split and draws the old equal halves again.
 */
class HingeWiringTest {

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

    /** Just `Page()`'s own body, bracket-matched so a call elsewhere in the file cannot pass this. */
    private fun pageBody(): String {
        val signature = readerScreen.indexOf("fun Page(display: Int, stitch: ScrollAxis? = null) {")
        check(signature >= 0) { "ReaderScreen.kt no longer declares Page(display, stitch) — has it moved?" }
        val open = readerScreen.indexOf('{', signature)
        var depth = 1
        var i = open + 1
        while (depth > 0) {
            when (readerScreen[i]) {
                '{' -> depth++
                '}' -> depth--
            }
            i++
        }
        return readerScreen.substring(open, i)
    }

    @Test
    fun `the slot reads the window's own separating vertical hinge`() {
        assertTrue(
            "Page() no longer reads windowPosture.separatingVerticalHingeBounds — a folded" +
                " window has nothing to avoid the hinge with.",
            pageBody().contains(
                "currentWindowAdaptiveInfoV2().windowPosture.separatingVerticalHingeBounds",
            ),
        )
    }

    @Test
    fun `a lone page is pinned to the hinge's inset rather than filling the whole slot`() {
        val body = pageBody()
        assertTrue(
            "Page() no longer asks hingeInset(split) for a lone page.",
            body.contains("val inset = hingeInset(split)"),
        )
        assertTrue(
            "A lone page no longer narrows to the inset's own width when one is found —" +
                " it would centre across the hinge again.",
            body.contains(".width(with(density) { inset.width.toDp() })"),
        )
        assertTrue(
            "A lone page no longer pins to the inset's own side.",
            body.contains("if (inset.atStart) Alignment.CenterStart else Alignment.CenterEnd"),
        )
    }

    @Test
    fun `a spread's two halves take the hinge split's own widths, not an equal weight`() {
        val body = pageBody()
        assertTrue(
            "The spread no longer asks hingeSpreadSplit for its own width.",
            body.contains("hingeSpreadSplit("),
        )
        assertTrue(
            "A spread's two halves no longer size themselves from split.leadingWidth and" +
                " split.trailingWidth — a hinge off-centre would split the pair down the" +
                " container's own midpoint again.",
            body.contains(
                "(if (half == 0) split.leadingWidth else split.trailingWidth).toDp()",
            ),
        )
        assertTrue(
            "A spread no longer draws the hinge's own gap between its two halves.",
            body.contains("Spacer(Modifier.width(with(density) { split.gap.toDp() })"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
