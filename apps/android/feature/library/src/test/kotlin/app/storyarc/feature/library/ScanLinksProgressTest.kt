package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The scan hands the progress store what it learned, so a rename keeps the reader's place.
 *
 * `ProgressStore.link` was written to close the window between a position recorded against a
 * path and the first rename of that file. Nothing called it. `ProgressStore.save` fills the
 * digest in as well, but only when the reader opens the publication again -- a reader who
 * tidies their folder first never gets that far, and loses their place without a word.
 *
 * **Text over the view model's source, and for the reason [SkippedScanTest]'s header gives:**
 * driving a walk through the view model needs an `Application`, a `ContentResolver` and a
 * document tree, and the wiring in question is one call at the end of one job. So the store's
 * own behaviour is asserted against a real database in `:core:persistence`'s
 * `ProgressStoreTest`, and this asserts that the scan actually reaches it. A tripwire, not a
 * proof.
 *
 * iOS drives the whole seam in `ScanLinksProgressTests`, because its store has an in-memory
 * mode on the host and its library model needs no device. The asymmetry is in the platforms.
 */
class ScanLinksProgressTest {

    /** The view model's source, with `//` prose removed. */
    private fun code(): String {
        val source = File(
            requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
                "$MODULE_DIRECTORY is not set -- see this module's build.gradle.kts"
            },
            VIEW_MODEL_SOURCE,
        )
        assertTrue("$VIEW_MODEL_SOURCE is not at ${source.absolutePath}", source.isFile)
        // The KDoc on the call quotes the defect in order to say it is closed, and a guard
        // that read the prose would pass on the documentation of the fix.
        return source.readText().lineSequence().joinToString("\n") { it.substringBefore("//") }
    }

    @Test
    fun `the scan hands every identity it learned to the progress store`() {
        assertTrue(
            "Nothing in the view model calls `$LINKED`. The scan computes a content digest" +
                " for every publication it finds and then throws it away, so a position" +
                " recorded against a path stays keyed to that path and the first rename" +
                " loses it silently.",
            LINKED in code(),
        )
    }

    @Test
    fun `it links once for the whole walk rather than once per publication`() {
        assertEquals(
            "The view model links in more than one place. Linking belongs at the end of the" +
                " walk, over the shelf the walk produced: a call inside the collect loop" +
                " reads the store once per file found, which is the cost `link` was shaped" +
                " to avoid.",
            1,
            code().split(LINKED).size - 1,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val VIEW_MODEL_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt"

        /** The call that closes the window. */
        const val LINKED = "progressStore?.link("
    }
}
