package app.storyarc.feature.epubreader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a publication already on the device opens like any other book, here too.
 *
 * The twin of `:feature:reader`'s `SolidArchiveHasNoNoticeTest`, which carries the reasoning at
 * length: `publication-formats` says a publication that cannot stream and is already offline
 * "opens directly with no notice, because the constraint was never about the format being
 * readable", nothing exists today to suppress, and so the only thing worth asserting is an
 * absence that fails the day somebody adds a notice.
 *
 * **This module is here because the premise was checked across three readers and the guard
 * covered two.** The 5.3 note records `:feature:reader`, `:feature:epubreader` and iOS's
 * `ReaderFeature` as checked; the guards read only the first and the third. A reflowable EPUB
 * is the one publication most likely to be fetched whole before it opens -- the Readium
 * navigator wants a file of its own, so every remote EPUB arrives as a download -- which makes
 * this the module a "you downloaded this" notice would most plausibly land in. iOS's
 * `EpubReaderFeature` is walked by `SolidArchiveHasNoNoticeTests.swift` in `StoryArcKit`, from
 * the sibling package, because `StoryArcEpub`'s own tests need a simulator and the gate has
 * none.
 */
class SolidArchiveHasNoNoticeTest {

    /**
     * Every Kotlin source in this module, at the path the build script hands to the test JVM.
     *
     * Deliberately not discovered, for `ReaderChromeWiringTest`'s reason: a walk up from the
     * working directory climbs out of the worktree under test. The tree is declared an input of
     * the test task, so adding a file re-runs this.
     */
    private val sources: List<File> by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own sources and will" +
                    " not go looking for them elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
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
        // A guard over an empty list passes forever.
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
                " being readable\". If a notice is genuinely wanted here, change the spec" +
                " first and then this test.",
            offenders.isEmpty(),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val MAIN_SOURCES = "src/main/kotlin"

        /** The same five tells `:feature:reader`'s twin lists, and for the same reason. */
        val NOTICE_TELLS = listOf(
            "StreamingCapability",
            "StreamingOffer",
            "DOWNLOAD_ONLY",
            "isSolid",
            "isStreamable",
        )
    }
}
