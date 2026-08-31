package app.storyarc.feature.epubreader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a reflowable publication offers no slider, and that the fill behind its contents row
 * says nothing twice.
 *
 * `ebook-reader`, *Pagination and progress*:
 *
 * > A reflowable publication SHALL report its position **in words, in one line**, and SHALL
 * > NOT draw a page slider. Pages are not the unit a novel is read in, and the app already
 * > refuses to treat a reflowable page number as a stable identity — a slider whose track is
 * > measured in those pages is that same claim in another form.
 *
 * **The absence is the assertion worth having.** A compiler does not notice a control
 * returning, and this is the one requirement in the change that is stated as a prohibition.
 * `ReadingPositionLineTest` in `:core:model` owns what the line *says*, over a pure type;
 * this owns what the reader *draws*, by reading its source, and is a tripwire rather than a
 * proof.
 */
class ReaderProgressTest {

    private val module: File by lazy {
        System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
    }

    private val code: String by lazy {
        SOURCES.joinToString("\n") { relative ->
            val file = File(module, "src/main/kotlin/app/storyarc/feature/epubreader/$relative")
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
    fun `a reflowable publication offers no slider, in the chrome or in the menu`() {
        assertTrue(
            "The reflowable reader declares a `Slider`. `ebook-reader` forbids it: a slider" +
                " whose track is measured in reflowable pages is the same claim as a" +
                " reflowable page number, which the app refuses to present. The table of" +
                " contents is how a reader goes somewhere else, and it is on the same menu.",
            !code.contains("Slider("),
        )
    }

    @Test
    fun `the line comes from the shared rule, not from this reader`() {
        assertTrue(
            "The reflowable reader's progress line is not built from `ReadingPositionLine`." +
                " Both readers answer `ebook-reader`'s progress display from the one rule in" +
                " `:core:model`, because a reader that says one thing on one platform and" +
                " another on the other is the divergence that module exists to prevent.",
            code.contains("ReadingPositionLine.of("),
        )
    }

    @Test
    fun `the coarse fill is flat, and decorative to assistive technology`() {
        assertTrue(
            "The reflowable reader's menu draws no coarse fill. `comic-reader` asks for the" +
                " position to be \"drawn as a fill behind the menu's own contents row\".",
            code.contains("LinearProgressIndicator("),
        )
        assertTrue(
            "The fill is not the flat `LinearProgressIndicator`. Material cautions that the" +
                " wavy variant \"may not be as visible\" at small sizes and says linear" +
                " indicators \"shouldn't be used in any elements smaller than 40dp\".",
            !code.contains("WavyProgressIndicator"),
        )
        assertTrue(
            "The fill is not cleared of semantics. `comic-reader`: \"the text is what conveys" +
                " the position\". A percentage announced twice is announced wrong.",
            code.contains("clearAndSetSemantics {}"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"

        val SOURCES = listOf("EpubChrome.kt", "EpubMenuSheet.kt", "EpubReaderOverlays.kt")
    }
}
