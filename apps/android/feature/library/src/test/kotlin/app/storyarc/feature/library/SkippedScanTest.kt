package app.storyarc.feature.library

import app.storyarc.core.format.LibraryScanner
import app.storyarc.core.format.ScanEvent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
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
 * library model; this stops at the scanner because Android's view model needs an
 * `Application`, a `ContentResolver` and a document tree to walk one, and the branch above is
 * a one-line exhaustive `when`.
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

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
    }
}
