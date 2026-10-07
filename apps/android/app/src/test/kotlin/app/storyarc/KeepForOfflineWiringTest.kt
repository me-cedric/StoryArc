package app.storyarc

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `keepForOffline` copies through [app.storyarc.core.format.ChunkedCopy], not one read.
 *
 * The regression: `file.writeBytes(source.read(0, source.length.toInt()))` reads a share's
 * whole file in a single call and holds it in memory to write it back out.
 * `source.length.toInt()` is the sharper half — a `Long` truncated to `Int` overflows above
 * 2 GiB, and one SMB read is capped by the server's read size well before that, so a share file
 * larger than either limit wrote nothing and was indexed as an empty file.
 * `ChunkedCopyTest` pins the fixed-chunk copy itself; this is the wiring, that
 * `keepForOffline` actually calls it.
 *
 * A source guard rather than a behaviour test: driving `keepForOffline` end to end needs a
 * registered `PublicationAccess` scheme and a `DownloadStore`, whose constructor is internal
 * to `core:persistence` and unavailable from this module without a fake `Context` — the same
 * trade `ReaderChromeWiringTest` names for its own defect. What can be asserted here is that
 * the one-shot read is gone and the chunked copy has taken its place.
 */
class KeepForOfflineWiringTest {

    private val source = "app/src/main/kotlin/app/storyarc/KeepForOffline.kt"

    @Test
    fun `the copy goes through ChunkedCopy`() {
        assertTrue(
            "keepForOffline no longer copies through ChunkedCopy",
            code().contains("ChunkedCopy.copy("),
        )
    }

    @Test
    fun `nothing reads the whole file into memory in one call`() {
        assertFalse(
            "keepForOffline reads the whole file in one call again — source.length.toInt()" +
                " overflows above 2 GiB and a single SMB read is capped by the server before that",
            withoutComments(code()).contains("source.read(0, source.length.toInt())"),
        )
    }

    private fun code(): String {
        val file = File(androidRoot, source)
        assertTrue("$source has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private fun withoutComments(text: String): String = text
        .replace(Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL), "")
        .lines()
        .joinToString("\n") { it.substringBefore("//") }

    private companion object {
        /** `apps/android`, found rather than hardcoded. See `ShelvesAskOneRuleTest`. */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
