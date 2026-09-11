package app.storyarc.feature.library

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a refresh of one source from its own screen says it is running.
 *
 * `sources`' *A refresh of one source from its own screen* is satisfied by one line:
 * `LibraryViewModel.testSource` marks the source `Connecting` **before** it asks, so the
 * detail screen's *Status* row has something true to read for as long as the ask takes.
 * Without the mark the row keeps its last answer, and a reader cannot tell a refresh from a
 * screen that is ignoring them.
 *
 * **This reads the source text, and that is a deliberate second choice**, for
 * `SourceRetryWiringTest`'s reason: `testSource` reaches the network, so a test that called
 * it would need one. Task 8.1 of `a-refresh-that-says-it-is-running` recorded that this
 * function was asserted by nothing on either platform, and this ends that on this one.
 * iOS's `SourceRefreshWiringTests` is the twin.
 *
 * It is a tripwire, not a proof. It says a call is written and that one call comes before
 * another. It never says a server answered.
 */
class SourceRefreshWiringTest {

    private fun read(path: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, path)
        if (!file.isFile) error("$path is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    /**
     * The body of `testSource`, not the whole file.
     *
     * `SourceHealth.probe` is called from more than one place in `LibraryViewModel.kt`, and
     * an unscoped search finds the wrong one — which is exactly what happened on the iOS
     * twin and reported the mark as coming after the ask when it comes before it.
     */
    private val body: String by lazy {
        val source = read(VIEW_MODEL)
        val start = source.indexOf("fun testSource(")
        if (start < 0) error("LibraryViewModel no longer has testSource — the detail screen cannot refresh one source")
        val end = source.indexOf("\n    fun ", start + 1).let { if (it < 0) source.length else it }
        source.substring(start, end)
    }

    @Test
    fun `the source is marked connecting before it is asked`() {
        val mark = body.indexOf("SourceConnectionState.Connecting")
        val ask = body.indexOf("SourceHealth.probe(")
        assertTrue(
            "testSource no longer marks the source Connecting, so its Status row says nothing while it asks",
            mark >= 0,
        )
        assertTrue("testSource no longer probes the source, so there is nothing to mark it for", ask >= 0)
        assertTrue(
            "the mark is written after the ask, so the row is only true once the answer is already in",
            mark < ask,
        )
    }

    @Test
    fun `a local folder is answered without a connecting mark`() {
        // A folder is read rather than reached, so *Connecting* would be a claim about a
        // network that is not involved. The guard returns before the mark.
        assertTrue(
            "testSource no longer answers a local folder separately, so a folder reads as connecting",
            body.contains("if (!SourceProbe.isRemote(source.kind))"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val VIEW_MODEL = "src/main/kotlin/app/storyarc/feature/library/LibraryViewModel.kt"
    }
}
