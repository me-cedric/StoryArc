package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `collections-and-reading-lists` tasks 7.3 and 7.14: a server reading list the reader is
 * inside answers the reader's next/previous offer before the local library's own guess does,
 * and a taken offer is fetched when it has no file yet. [ServerListContextTest] and
 * [ServerListContextIntegrationTest] in `:feature:library` prove what the answer is and what
 * taking it fetches; this is only that `ReaderHost` asks for both.
 */
class ReaderHostServerListWiringTest {

    @Test
    fun `the reader asks for an offer it can open, and opens a taken one through openEntry`() {
        val host = read(READER_HOST)
        assertTrue(
            "ReaderHost no longer asks offeredNext for the next entry, so a server list's own" +
                " order is never offered, and a row with no file can be offered again.",
            host.contains("nextInSeries = host.library.offeredNext(publication)"),
        )
        assertTrue(
            "ReaderHost no longer asks offeredPrevious for the previous entry.",
            host.contains("previousInSeries = host.library.offeredPrevious(publication)"),
        )
        assertTrue(
            "ReaderHost no longer opens a taken offer through openEntry, so a server list's" +
                " next entry, which has no file yet, opens nothing.",
            host.contains("onOpen = host::openEntry"),
        )
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val READER_HOST = "app/src/main/kotlin/app/storyarc/ReaderHost.kt"

        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
