package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a fixed-page publication keeps its slider, in the menu, and that the fill behind the
 * contents row says nothing twice.
 *
 * `comic-reader`, *Page slider with thumbnails* and *Where the reader is, at a glance*:
 *
 * > **WHEN** a user opens the reader's menu on a publication with fixed pages and drags the
 * > page slider **THEN** a thumbnail of the target page follows the drag …
 * > **AND** releasing jumps there and dismisses the menu, with a control to return to the
 * > previous position
 * > …
 * > **AND** the text is what conveys the position, so the fill may be absent without
 * > anything being lost — it is not the only indication
 *
 * `ReadingPositionLineTest` in `:core:model` owns what a reflowable line *says*, and it is a
 * real unit test over a pure type. This owns where the slider and the fill are *drawn*, which
 * no JVM test can measure — so it reads the source, and it is a tripwire rather than a proof.
 *
 * `:feature:epubreader`'s `ReaderProgressTest` is the other half: it asserts the *absence* of
 * a slider, which is what `ebook-reader` requires of a reflowable publication.
 */
class ReaderProgressTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val code: String by lazy {
        SOURCES.joinToString("\n") { relative ->
            val file = File(module, "src/main/kotlin/app/storyarc/feature/reader/$relative")
            if (!file.isFile) {
                error("$relative is not under ${module.absolutePath} — has it moved?")
            }
            val withoutBlocks = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
                .replace(file.readText(), "")
            withoutBlocks.lineSequence().joinToString("\n") { line ->
                val comment = line.indexOf("//")
                if (comment >= 0) line.substring(0, comment) else line
            }
        }
    }

    @Test
    fun `a fixed-page publication keeps its slider, its thumbnail, and the way back`() {
        val kept = listOf(
            "the slider itself" to "Slider(",
            "the thumbnail that follows the drag" to "ScrubThumbnail(",
            "the scrub that moves nothing until released" to "onValueChangeFinished",
            "the menu leaving on release" to "isReaderMenuOpen = false",
            "the way back from the jump" to "returnFromJump",
        )

        for ((what, spelling) in kept) {
            assertTrue(
                "The comic reader has lost $what — `$spelling` is not in its menu." +
                    " `comic-reader` keeps the slider \"in the reader's menu rather than over" +
                    " the page\", with the thumbnail follow intact, and requires that" +
                    " \"releasing jumps there and dismisses the menu, with a control to" +
                    " return to the previous position\".",
                code.contains(spelling),
            )
        }
    }

    @Test
    fun `the coarse fill is flat, and decorative to assistive technology`() {
        assertTrue(
            "The comic reader's menu draws no coarse fill. `comic-reader` asks for the" +
                " position to be \"drawn as a fill behind the menu's own contents row\".",
            code.contains("LinearProgressIndicator("),
        )
        assertTrue(
            "The fill is not the flat `LinearProgressIndicator`. Material cautions that the" +
                " wavy variant \"may not be as visible\" at small sizes and says linear" +
                " indicators \"shouldn't be used in any elements smaller than 40dp\" — a thin" +
                " fill behind a list row is precisely that case.",
            !code.contains("WavyProgressIndicator"),
        )
        assertTrue(
            "The fill is not cleared of semantics. `comic-reader`: \"the text is what conveys" +
                " the position, so the fill may be absent without anything being lost — it is" +
                " not the only indication\". A page number announced twice is a page number" +
                " announced wrong.",
            code.contains("clearAndSetSemantics {}"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"

        val SOURCES = listOf("ReaderMenuSheet.kt", "ReaderScreen.kt")
    }
}
