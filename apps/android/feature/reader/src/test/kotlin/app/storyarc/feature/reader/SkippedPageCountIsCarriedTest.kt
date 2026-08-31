package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the count of pages an archive could not read reaches the reader's own controls.
 *
 * `publication-formats`, *Corrupt archive*:
 *
 * > **THEN** the app opens whatever pages it can read and states how many were skipped,
 * > rather than refusing the whole publication
 * > **AND** the count is shown in the reader's own controls, where it recedes with them,
 * > because it is a fact about the file rather than about the page in front of the reader
 *
 * A verify pass on `format-scope-and-libraries` found this scenario asserted on the Android
 * side only at the **format** layer: `ComicArchiveTest` proves the archive counts correctly,
 * and nothing proved the reader ever showed the number. A count computed and dropped
 * satisfies every test there was.
 *
 * **What this is, and what it is not.** It reads source text. `ReaderViewModel` takes a
 * `ContentResolver`, so constructing one needs Robolectric or a device, and this module has
 * neither — every test in it is a source-level tripwire for that reason, and
 * `SolidArchiveHasNoNoticeTest` explains the trade at length. So this proves the **wiring**:
 * that the view model publishes the archive's count and that the menu renders it. It cannot
 * prove a number appeared on a screen.
 *
 * That is worth having anyway, because the regression it guards is silent. Delete the
 * assignment and the format layer still counts, the app still opens the comic, every test
 * still passes, and the reader is never told. An instrumented test that opened
 * `truncated.cbz` and read the notice would be strictly better, and the day this module has
 * one, delete this.
 *
 * iOS reaches the same scenario through `ReaderModelTests`, which can construct its model on
 * the host.
 */
class SkippedPageCountIsCarriedTest {

    private val sources: List<File> by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own sources and will" +
                    " not go looking for them elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val tree = File(module, MAIN_SOURCES)
        if (!tree.isDirectory) {
            error("$MAIN_SOURCES is not under ${module.absolutePath} — has it moved?")
        }
        tree.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
    }

    private fun source(name: String): String {
        val file = sources.firstOrNull { it.name == name }
            ?: error("$name is not in this module any more — has it moved? A guard that cannot find what it guards passes for ever.")
        return file.readText()
    }

    @Test
    fun `the view model publishes the count the archive gave it`() {
        val text = source("ReaderViewModel.kt")

        assertTrue(
            "ReaderViewModel no longer takes the skipped-page count from the opened archive." +
                " The format layer would go on counting and no reader would ever be told.",
            text.contains("_skippedPageCount.value = opened.skippedPageCount"),
        )
        assertTrue(
            "ReaderViewModel no longer exposes skippedPageCount, so nothing can render it.",
            text.contains("val skippedPageCount: StateFlow<Int>"),
        )
    }

    @Test
    fun `the reader's own controls render it`() {
        // "In the reader's own controls, where it recedes with them" — so the assertion is
        // about the menu sheet specifically, not about the count appearing somewhere.
        val text = source("ReaderMenuSheet.kt")

        assertTrue(
            "The reader's menu no longer shows how many pages were skipped. The count is a" +
                " fact about the file, and `publication-formats` puts it here rather than over" +
                " the page.",
            text.contains("SkippedNotice(facts.skippedPageCount)"),
        )
    }

    @Test
    fun `the screen still hands the count to the menu`() {
        // The third link, and the one a refactor is likeliest to drop: the view model
        // publishes, the sheet renders, and this is what joins them.
        val text = source("ReaderScreen.kt")

        assertTrue(
            "ReaderScreen no longer collects the skipped count from the view model.",
            text.contains("viewModel.skippedPageCount"),
        )
        assertTrue(
            "ReaderScreen no longer passes the skipped count to the menu.",
            text.contains("skippedPageCount = skipped"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val MAIN_SOURCES = "src/main/kotlin"
    }
}
