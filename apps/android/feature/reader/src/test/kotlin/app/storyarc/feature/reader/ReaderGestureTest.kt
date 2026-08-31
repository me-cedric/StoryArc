package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That fewer controls did not become fewer ways in.
 *
 * `comic-reader`, *Fewer controls is not fewer ways in*:
 *
 * > **WHEN** a user uses any gesture the reader supported before this change — edge tap,
 * > swipe, pinch, drag to zoom, or the mirrored equivalents in right-to-left mode
 * > **THEN** it behaves exactly as it did, because moving controls into a menu must not
 * > make the reader harder to drive
 *
 * **This asserts the recognisers are still declared. It does not assert they fire.** That
 * distinction matters and is not a hedge: what it can catch is a gesture *deleted* while the
 * chrome was being cut down, which is the failure mode a declutter actually has. What it
 * cannot catch is a gesture that still exists and no longer works — for that the reader has
 * to be on a screen, and nothing in this repository runs this module's instrumented tests.
 *
 * The right-to-left assertion is the one worth reading twice. The mirroring is a single
 * expression, and `comic-reader` says the edge zones are "mirrored in right-to-left mode" —
 * which they are, for free, because the *display order* is reversed rather than the zones.
 * Deleting that reversal is a one-line edit that leaves everything compiling and opens every
 * manga at the wrong end. `PageZoomTest` and `CurlTurnTest` measure the arithmetic these
 * gestures drive; this only says the gestures are still wired to it.
 *
 * iOS keeps the same guard as `ReaderGestureTests`.
 */
class ReaderGestureTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private fun code(relative: String): String {
        val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/$relative")
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

    /** Every gesture the reader answered before the chrome was cut down. */
    private val gestures = listOf(
        Triple("the edge tap that turns a page", "ReaderScreen.kt", "isEdgeTap(point, size)"),
        Triple("the edge zones themselves", "ReaderScreen.kt", "EDGE_ZONE_FRACTION"),
        Triple("the centre tap that reveals the chrome", "ReaderScreen.kt", "fun handleTap("),
        Triple("the double tap to zoom", "ReaderScreen.kt", "onDoubleTap"),
        Triple("the swipe between pages", "ReaderScreen.kt", "HorizontalPager("),
        Triple("the pinch to zoom", "PageZoom.kt", "fun pinched("),
        Triple("the drag to pan a zoomed page", "PageZoom.kt", "pan: Offset"),
        Triple(
            "the right-to-left mirroring of the display order",
            "ReaderScreen.kt",
            "if (isRightToLeft) slotCount - 1 - display else display",
        ),
    )

    @Test
    fun `no gesture was lost when the chrome was cut to two controls`() {
        for ((what, file, spelling) in gestures) {
            assertTrue(
                "$what is gone from $file — `$spelling` is not in it. `comic-reader` requires" +
                    " every gesture the reader supported before the declutter to behave" +
                    " exactly as it did: \"moving controls into a menu must not make the" +
                    " reader harder to drive\".",
                code(file).contains(spelling),
            )
        }
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
    }
}
