package app.storyarc.core.format

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A folder of audio files, read as one audiobook.
 *
 * `publication-formats`: "it is treated as a single audiobook whose parts play in that
 * order, **by the same ordering rule that makes a folder of images one comic**". So this
 * reuses [PageOrdering.naturalCompare] rather than restating it — the digit-run rule that
 * puts `part10` after `part2` is the one that already produced a cross-platform
 * divergence once, and a second copy of it is a second chance to diverge.
 *
 * Asserted against the shared corpus in `packages/test-fixtures`, read from disk rather
 * than from a literal, so regenerating the fixtures differently fails it. iOS's
 * `AudiobookFolderTests` asserts the same cases.
 */
class AudiobookFolderTest {

    @Test
    fun `a folder's parts play in natural order`() {
        // The trap the fixture exists for: `part10` sorts after `part2`, which lexical
        // order gets wrong.
        val parts = AudiobookFolder.open(FixtureCorpus.file("audiobooks/folder-parts")).parts
        assertEquals(listOf("part1.mp3", "part2.mp3", "part10.mp3"), parts.map { it.path })
    }

    @Test
    fun `a mixed folder takes only its audio`() {
        // Two audio files against one image. `FolderKind` already decided this folder is
        // an audiobook; what this pins is that the image does not become a part of it.
        val parts = AudiobookFolder.open(FixtureCorpus.file("audiobooks/mixed-folder")).parts
        assertEquals(listOf("part1.mp3", "part2.mp3"), parts.map { it.path })
    }

    @Test
    fun `a part is named for the listener, not for the file`() {
        // A **product decision**, recorded as one in `design.md`: "naming the chapter, not
        // the file — `01 - track.mp3` is not what a listener is in the middle of". A
        // folder carries no chapter names, so the best available name is the file's own
        // with its extension and its ordering prefix taken off.
        assertEquals("Part 1", AudiobookFolder.partTitle("01 - part 1.mp3"))
        assertEquals("Chapter Two", AudiobookFolder.partTitle("02_Chapter Two.m4a"))
        assertEquals("Prologue", AudiobookFolder.partTitle("Prologue.flac"))
        // A name that is *only* its ordering prefix keeps the whole of it, exactly as
        // written. Stripping it would leave an empty row, and inventing "Part 3" would be
        // stating something the file does not say.
        assertEquals("03", AudiobookFolder.partTitle("03.mp3"))
    }

    @Test
    fun `an empty part is skipped rather than played`() {
        // The same rule a zero-length page gets: counted, not shown. `publication-formats`
        // asks a damaged audiobook to play "what it can" and state "how much it could
        // not", and a file with no bytes is the cheapest case of that.
        val folder = AudiobookFolder.of(
            listOf(
                AudiobookFolder.Candidate("part1.mp3", bytes = 1_000),
                AudiobookFolder.Candidate("part2.mp3", bytes = 0),
                AudiobookFolder.Candidate("part3.mp3", bytes = 1_000),
            ),
        )
        assertEquals(listOf("part1.mp3", "part3.mp3"), folder.parts.map { it.path })
        assertEquals(1, folder.skippedPartCount)
    }

    @Test
    fun `entries that are neither audio nor evidence are ignored`() {
        val folder = AudiobookFolder.of(
            listOf(
                AudiobookFolder.Candidate("part1.mp3", bytes = 1_000),
                AudiobookFolder.Candidate("cover.png", bytes = 1_000),
                AudiobookFolder.Candidate(".DS_Store", bytes = 1_000),
                AudiobookFolder.Candidate("._part1.mp3", bytes = 1_000),
                AudiobookFolder.Candidate("__MACOSX/part1.mp3", bytes = 1_000),
                AudiobookFolder.Candidate("notes.txt", bytes = 1_000),
            ),
        )
        assertEquals(listOf("part1.mp3"), folder.parts.map { it.path })
        // A resource fork is not a damaged part, so it is not counted as one.
        assertEquals(0, folder.skippedPartCount)
    }

    @Test
    fun `a folder with no audio is not an audiobook`() {
        assertTrue(AudiobookFolder.of(emptyList()).parts.isEmpty())
    }
}
