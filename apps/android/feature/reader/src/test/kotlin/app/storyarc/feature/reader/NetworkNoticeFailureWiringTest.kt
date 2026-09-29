package app.storyarc.feature.reader

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The download offer says when it did not start, rather than firing and forgetting.
 *
 * The regression: `onDownload` used to be `() -> Unit`, called and never awaited. A failed
 * copy — the share is still down, which is the entire reason the offer exists — looked
 * exactly like nothing happened; a reader who tapped it had no way to tell a slow transfer
 * from a silently refused one. `keptForOffline`/`ChunkedCopy` closed the copy itself; this is
 * the notice's own half, that a `false` answer is shown rather than swallowed.
 *
 * **So this test reads the source text**, for `ReaderChromeWiringTest`'s reason: the honest
 * test composes `NetworkNotice` and taps the download button, which this module has no
 * Robolectric Compose harness for yet. A guard that runs beats a better one that does not.
 * iOS keeps the same behaviour in `NetworkNotice.swift`, proved with a real `@State` toggle
 * a SwiftUI preview can drive.
 */
class NetworkNoticeFailureWiringTest {

    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, NOTICE_SOURCE)
        if (!file.isFile) {
            error("$NOTICE_SOURCE is not under ${module.absolutePath} — has it moved?")
        }
        file.readText()
    }

    @Test
    fun `the download's answer decides whether the failure text shows`() {
        assertTrue(
            "NetworkNotice no longer reads onDownload's own answer into downloadFailed.",
            source.contains("downloadFailed = !onDownload()"),
        )
    }

    @Test
    fun `the failure sentence is drawn from the string this test names`() {
        assertTrue(
            "NetworkNotice no longer references reader_offline_download_failed.",
            source.contains("R.string.reader_offline_download_failed"),
        )
    }

    @Test
    fun `the failure text is gated on the same flag the answer sets`() {
        // Loose on purpose — asserting the exact `if` would break on a harmless
        // reformatting — but the flag that gates the failure sentence must be the one the
        // download's own answer writes, or the two could disagree.
        assertTrue(
            "The failure text is not gated on downloadFailed.",
            source.contains("if (downloadFailed)"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val NOTICE_SOURCE = "src/main/kotlin/app/storyarc/feature/reader/NetworkNotice.kt"
    }
}
