package app.storyarc

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * StoryArc is offered for an audiobook the way it is offered for a comic.
 *
 * `local-library`, *Open-in from another app*:
 *
 * > **WHEN** a user chooses StoryArc from a share sheet, an "Open with" intent, or a file
 * > manager
 * > **THEN** the publication opens directly in the reader
 *
 * An audiobook became a supported publication in this change and the intent filters did not
 * follow it: the `VIEW` filters named CBZ, CBR, CB7, CBT, EPUB and PDF and no audio at all,
 * so a reader who tapped an M4B in a file manager never saw StoryArc in the list. There is no
 * way in from there that does not start with configuring a source, which is the thing this
 * requirement exists to make unnecessary.
 *
 * **Two filters, because one is not enough** — the same reason the comic archives need two.
 * A provider that knows an M4B calls it `audio/mp4`; most file managers hand one over as
 * `application/octet-stream`, and only the extension gets StoryArc into the list.
 *
 * Asserted over the source manifest rather than the merged one, because this is about what
 * the app *declares*: nothing merges these in, and the emulator confirmed the result — the
 * system's "Open with" sheet lists StoryArc for `sea-room.m4b`.
 */
class AudiobookAppearsInTheOpenWithListTest {

    private val manifest = "app/src/main/AndroidManifest.xml"

    @Test
    fun `the audio containers are named by MIME type`() {
        val declared = code()
        for (type in listOf("audio/mp4", "audio/mpeg", "audio/flac", "audio/ogg")) {
            assertTrue(
                "$type is not in the manifest, so a provider that knows the type will not" +
                    " offer StoryArc for it",
                declared.contains("""android:mimeType="$type""""),
            )
        }
    }

    @Test
    fun `and by extension, in both cases`() {
        val declared = code()
        // `.m4b` first: it is the format this change exists to open and the one with no MIME
        // type a provider reliably knows.
        for (extension in listOf("m4b", "m4a", "mp3", "flac", "ogg", "opus")) {
            assertTrue(
                ".$extension is not in the manifest, so a file manager handing one over as" +
                    " application/octet-stream will not offer StoryArc",
                declared.contains(""".*\\.$extension""""),
            )
            assertTrue(
                ".${extension.uppercase()} is missing; a pathPattern matches literally",
                declared.contains(""".*\\.${extension.uppercase()}""""),
            )
        }
    }

    private fun code(): String {
        val file = File(androidRoot, manifest)
        assertTrue("$manifest has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /** `apps/android`, found rather than hardcoded. See `ShelvesAskOneRuleTest`. */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
