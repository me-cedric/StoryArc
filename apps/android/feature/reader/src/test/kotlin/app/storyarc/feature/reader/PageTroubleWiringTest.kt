package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `decode` scopes `pageWaitStarted`/`pageFailingSince` to the page on screen, over a share,
 * and only the first failure starts the 60s clock.
 *
 * `network-share`'s *Connection drops while reading*: the notice used to count from a
 * failed read anywhere -- a prefetched neighbour's, on a local file same as a share -- and
 * every retry restarting the 60s clock rather than one continuous count from the first
 * failure. [PageRecoveryTest] and [PageBlockedSinceTest] pin what they can reach without a
 * share to fail on cue; this is the one thing left, and it needs exactly that.
 *
 * **So this test reads the source text**, for `SmbTransferWiringTest`'s reason: driving a
 * real failure over `smb://` and a real success after it needs a share on a schedule this
 * suite does not control. A guard that runs beats a better one that does not. iOS keeps the
 * same guard in `PageTroubleWiringTests.swift`.
 */
class PageTroubleWiringTest {

    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and " +
                    "will not go looking for it elsewhere — run it through Gradle " +
                    "(`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the " +
                    "property from the module directory.",
            )
        val file = File(module, DECODING_SOURCE)
        if (!file.isFile) {
            error("$DECODING_SOURCE is not under ${module.absolutePath} — has it moved?")
        }
        file.readText()
    }

    @Test
    fun `only the page on screen, over a share, is tracked`() {
        assertTrue(
            "decode no longer scopes the network trouble it tracks to the current page over a share.",
            source.contains(
                """val tracksNetwork = index == currentIndex && path.startsWith("smb://")""",
            ),
        )
    }

    @Test
    fun `neither field is touched unconditionally`() {
        assertTrue(source.contains("if (tracksNetwork) pageWaitStarted = System.currentTimeMillis()"))
        assertTrue(source.contains("if (tracksNetwork) pageWaitStarted = null"))
    }

    @Test
    fun `only the first failure starts the clock`() {
        assertTrue(
            "decode no longer guards pageFailingSince against a later retry restarting it.",
            source.contains("if (tracksNetwork && pageFailingSince == null)"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val DECODING_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/ReaderDecoding.kt"
    }
}
