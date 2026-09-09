package app.storyarc

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * A file the system handed over is read through the descriptor it came with, never by path.
 *
 * `local-library`: the app "SHALL open a supported publication handed to it by the system
 * without requiring the user to configure a source first".
 *
 * **The defect this guards, measured rather than imagined.** `OpenedFile.index` digested
 * `File(source.descriptorPath)` — `/proc/self/fd/N` — which re-opens the file *by name*. A
 * file the app reached only through a provider's grant is not one the app may open by name,
 * and `MediaStore` audio is exactly that case: the bytes are owned by `media_rw` and the app
 * holds no media permission. So every audiobook handed over from a file manager or the
 * system's own picker failed with
 *
 *     FileNotFoundException: /proc/self/fd/117: open failed: EACCES (Permission denied)
 *
 * and the reader was told the file was one StoryArc "does not recognise" — the one wording
 * `local-library` forbids for a format it supports. Seen on `storyarc-j6` on 2026-09-01.
 *
 * The source is already open, `RandomAccessSource` is the interface ADR-0008 exists for, and
 * `PublicationIndexer.contentDigest` takes one. The fix is which overload is called, which is
 * exactly the kind of thing that gets undone by somebody reaching for the nearest `File`.
 *
 * A source guard rather than a behaviour test, and the reason is worth stating: reproducing
 * it needs a provider whose bytes the app cannot open by path, which on a device means the
 * media store and in a unit test means nothing at all. What can be asserted here is that the
 * path is not taken.
 */
class HandedOverFileIsReadThroughItsSourceTest {

    private val source = "app/src/main/kotlin/app/storyarc/OpenedFile.kt"

    @Test
    fun `the digest is taken from the open source`() {
        assertTrue(
            "OpenedFile no longer digests the source it already has open",
            code().contains("PublicationIndexer.contentDigest(source)"),
        )
    }

    @Test
    fun `nothing re-opens the handed-over file by its descriptor path`() {
        // Wider than the `File(...)` call that failed, and deliberately: the path is dead in
        // two different ways. A provider's grant does not permit opening it by name at all,
        // and `use` closes the descriptor the moment the index returns. `:core:format` still
        // reads one — libarchive and `PdfRenderer` want a path — but it reads it while the
        // source is open, which is the difference.
        assertFalse(
            "OpenedFile reaches for a descriptor path, which a provider's grant does not" +
                " permit and which `use` closes anyway — see the EACCES recorded above",
            withoutComments(code()).contains("source.descriptorPath"),
        )
    }

    /**
     * The second defect on the same line, measured on an HD1911 on 2026-09-08.
     *
     * `Outcome.Opened` carried `source.descriptorPath` and was built *inside* the `use` block,
     * so every caller received a path that closed as the index returned. A comic and a PDF
     * survived it by opening the location straight away. An audiobook did not, because the
     * player needs the location for as long as it plays — so `am start VIEW` on an audio
     * content URI opened no player.
     *
     * The `Uri` is the fix. It outlives the descriptor, media3 reads it through
     * `ContentDataSource`, and `PublicationAccess` already branches on the `content://` prefix
     * for both readers.
     */
    @Test
    fun `the location a caller keeps is the content Uri`() {
        assertTrue(
            "OpenedFile no longer hands back the Uri, so a handed-over audiobook opens nothing",
            withoutComments(code()).contains("Outcome.Opened(publication, uri.toString())"),
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
