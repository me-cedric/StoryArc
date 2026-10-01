package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `collections-and-reading-lists` task 7.3: a server reading list the reader is actually
 * inside answers the reader's next/previous offer before the local library's own guess does
 * — [ServerListContextTest] and [ServerListContextIntegrationTest] in `:feature:library`
 * prove what that answer is; this is only that `ReaderHost` asks for it first.
 */
class ReaderHostServerListWiringTest {

    @Test
    fun `the reader asks the server list before the local library`() {
        val host = read(READER_HOST)
        assertTrue(
            "ReaderHost no longer asks ServerListContext for the next entry, so a server" +
                " list's own order is never offered — only the local library's guess.",
            host.contains("ServerListContext.next(publication) ?: host.library.next(publication)"),
        )
        assertTrue(
            "ReaderHost no longer asks ServerListContext for the previous entry.",
            host.contains("ServerListContext.previous(publication) ?: host.library.previous(publication)"),
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
