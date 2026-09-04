package app.storyarc.feature.library

import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.ScanEvent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * A real scan of two files that fail differently, and what the library keeps of it.
 *
 * The rules are asserted in [SkippedPublicationsTest]; this is the wiring, and it is the half
 * that was broken. `LibraryScanner` emitted `ScanEvent.Skipped(path, reason)` from the
 * beginning; `rescan` matched `is ScanEvent.Skipped -> Unit`. Everything above that line was
 * correct and a reader still got a bare count.
 *
 * Two corpus files that fail for **different** reasons, because one reason standing in for two
 * is exactly what the count was doing. `refused.cb7` is a container StoryArc does not read;
 * `password-protected.cbz` is a ZIP it does read whose entries it cannot.
 *
 * **`rar4-solid.cbr` is deliberately not the second file**, though the change's task list
 * names it: a solid RAR4 is *found* and marked unopenable on purpose — the library should list
 * it and say why rather than drop it — so it never reaches a skip at all.
 *
 * iOS asserts the same pair in `SkippedScanTests`, which can go further and drive its whole
 * library model; the three tests here stop at the scanner because Android's view model needs
 * an `Application`, a `ContentResolver` and a document tree to walk one, and the branch above
 * is a one-line exhaustive `when`.
 *
 * **The fourth test asks the view model anyway, in the only way it can: as text.** There
 * turned out to be two scan paths, and only one of them had been fixed — see that test for
 * the second one and why it is gone rather than repaired.
 */
class SkippedScanTest {

    /** The committed fixture corpus, from this module's own directory rather than a walk. */
    private val corpus: File = File(
        requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
            "$MODULE_DIRECTORY is not set — see this module's build.gradle.kts"
        },
        // apps/android/feature/library -> repository root
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    private fun folder(vararg files: String): File {
        val root = Files.createTempDirectory("skipped").toFile()
        for (file in files) {
            corpus.resolve(file).copyTo(root.resolve(File(file).name))
        }
        return root
    }

    private suspend fun refusals(root: File): SkippedPublications {
        val met = mutableListOf<SkippedPublications.Entry>()
        LibraryScanner.scan(root).collect { event ->
            if (event is ScanEvent.Skipped) met += event.asRefusal()
        }
        return SkippedPublications().settling(met)
    }

    @Test
    fun `two files that fail differently keep two different reasons`() = runTest {
        val root = folder("comics/refused.cb7", "comics/password-protected.cbz")
        try {
            val skipped = refusals(root)

            assertEquals(SkippedPublications.Notice.Several(2), skipped.notice)
            assertEquals(
                setOf("refused.cb7", "password-protected.cbz"),
                skipped.entries.map { it.name }.toSet(),
            )
            val reasons = skipped.entries.associate { it.name to it.reason }
            // The CB7's reason names the container, which is the whole point of
            // `publication-formats` wording it rather than the library inventing one.
            assertTrue(reasons.getValue("refused.cb7"), "CB7" in reasons.getValue("refused.cb7"))
            // Not merged. This is the assertion a count could never satisfy.
            assertNotEquals(
                reasons.getValue("refused.cb7"),
                reasons.getValue("password-protected.cbz"),
            )
            assertTrue(skipped.entries.all { it.reason.isNotBlank() })
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `one failure names the publication rather than counting it`() = runTest {
        val root = folder("comics/refused.cb7")
        try {
            val notice = refusals(root).notice

            assertTrue("$notice should name the publication", notice is SkippedPublications.Notice.One)
            assertEquals("refused.cb7", (notice as SkippedPublications.Notice.One).name)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `a scan that opens everything says nothing`() = runTest {
        val root = folder("comics/single-page.cbz")
        try {
            assertEquals(SkippedPublications.Notice.Nothing, refusals(root).notice)
        } finally {
            root.deleteRecursively()
        }
    }

    /**
     * And the view model keeps exactly one scan path, which does not discard a refusal.
     *
     * **There were two, and the second still had the line the first had lost.** `rescan` was
     * fixed; `scan(File)` beside it went on matching `is ScanEvent.Skipped -> Unit` and never
     * touched `_skipped`, so a scan through it would neither raise the notice nor clear one
     * already up. It had no caller anywhere — its last one left `LibraryScreen` in `bce7dfb3`,
     * the same commit that gave it a comment claiming the instrumented tests used it, and
     * `:feature:library` has never had an `androidTest` source set for them to live in — so
     * it is gone rather than repaired. This is what stops the pair coming back: a second walk
     * added later gets the same line back with nothing to notice, exactly as the first one
     * did.
     *
     * **Text over the view model's source, and for the reason this file's own header gives:**
     * driving a walk through the view model needs an `Application`, a `ContentResolver` and a
     * document tree, and the branch in question is one arm of a `when`. So the three tests
     * above assert the rules against a real scan of real files, and this one asserts that
     * nothing in the view model throws the result of one away. A tripwire, not a proof.
     */
    @Test
    fun `the view model has one scan path and it keeps what was refused`() {
        val source = File(
            requireNotNull(System.getProperty(MODULE_DIRECTORY)) {
                "$MODULE_DIRECTORY is not set — see this module's build.gradle.kts"
            },
            VIEW_MODEL_SOURCE,
        )
        assertTrue("$VIEW_MODEL_SOURCE is not at ${source.absolutePath}", source.isFile)
        // Prose stripped: the KDoc on `rescan` and the comments around the settling call
        // both quote the branch below in order to say it is gone, and a guard that read
        // those would pass on the documentation of the fix.
        val code = source.readText().lineSequence().joinToString("\n") { it.substringBefore("//") }

        assertFalse(
            "The view model matches `$DISCARDED` again. That is the line this change existed" +
                " to remove: a walk that hits it neither raises the notice nor clears one" +
                " that is already up, and `rescan` settling correctly elsewhere does not" +
                " help a reader whose scan went the other way.",
            code.contains(DISCARDED),
        )
        assertTrue(
            "Nothing in the view model settles `_skipped`, so a refusal is collected and" +
                " never reaches the notice. Refusals are settled once after every tree —" +
                " settling replaces the list rather than adding to it.",
            code.contains(SETTLED),
        )
        assertEquals(
            "The view model collects `ScanEvent.Skipped` in more than one place, so there is" +
                " a second scan path and the two can disagree about what a reader is told." +
                " One walk, one settle.",
            1,
            code.split(REFUSAL).size - 1,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val VIEW_MODEL_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt"

        /** The branch that threw a refusal away. */
        const val DISCARDED = "is ScanEvent.Skipped -> Unit"

        /** The branch that keeps one, and the call that turns the pairs into the notice. */
        const val REFUSAL = "is ScanEvent.Skipped ->"
        const val SETTLED = "_skipped.value = _skipped.value.settling("
    }
}
