package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a downloaded solid archive opens like any other book.
 *
 * `publication-formats`, *Streaming capability per format*:
 *
 * > **WHEN** a publication that cannot stream is already available offline
 * > **THEN** it opens directly with no notice, because the constraint was never about the
 * > format being readable
 *
 * **This is a guard against a notice arriving, not a proof that one is absent today.** No
 * solid-archive or streaming notice exists in either app to suppress, so nothing here can
 * measure a suppression: `StreamingOffer.of` answering `Open` for a local `DOWNLOAD_ONLY`
 * publication is the rule, and `StreamingOfferTest` asserts it. What was missing was anything
 * that fails the day somebody adds the notice, and a scenario nothing can fail is a scenario
 * nothing protects.
 *
 * So the assertion is an absence, across the module that opens comics. The reader is handed a
 * path and a [app.storyarc.core.model.Publication]; it has no business reading how that
 * publication was obtained. `NetworkNotice` is the shape a notice takes here and it is gated
 * on one thing -- how long a page has been blocked on the network -- which is a fact about
 * *now* and is null for a file on the device. A notice about the container would be gated on
 * the capability instead, and would therefore have to name it.
 *
 * iOS keeps the same guard in `SolidArchiveHasNoNoticeTests.swift`.
 */
class SolidArchiveHasNoNoticeTest {

    /**
     * Every Kotlin source in this module, at the path the build script hands to the test JVM.
     *
     * Deliberately not discovered. [MODULE_DIRECTORY] is set from `projectDir` in
     * `build.gradle.kts`, which is the module being built by construction; a walk up from the
     * working directory leaves the worktree. The tree is declared an input of the test task
     * there, so adding a file re-runs this.
     */
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

    @Test
    fun `the reader has sources to read`() {
        // A guard over an empty list passes forever. This is the one assertion that fails if
        // the walk stops finding anything.
        assertTrue("No Kotlin sources found under $MAIN_SOURCES", sources.size > 5)
    }

    @Test
    fun `the reader says nothing about how a publication was obtained`() {
        val offenders = sources.filter { file ->
            val text = file.readText()
            NOTICE_TELLS.any { text.contains(it) }
        }
        assertTrue(
            "These files name a streaming capability: ${offenders.map { it.name }}." +
                " A publication that is on the device opens directly with no notice —" +
                " `publication-formats` says the constraint \"was never about the format" +
                " being readable\", and a solid RAR5 that has been downloaded is a comic like" +
                " any other. If a notice is genuinely wanted here, change the spec first and" +
                " then this test.",
            offenders.isEmpty(),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val MAIN_SOURCES = "src/main/kotlin"

        /**
         * What a notice about the container would have to mention to decide when to appear.
         *
         * `isSolid` and `isStreamable` are the format layer's own names for the two facts; the
         * enum and the offer are how the rest of the app carries them.
         */
        val NOTICE_TELLS = listOf(
            "StreamingCapability",
            "StreamingOffer",
            "DOWNLOAD_ONLY",
            "isSolid",
            "isStreamable",
        )
    }
}
