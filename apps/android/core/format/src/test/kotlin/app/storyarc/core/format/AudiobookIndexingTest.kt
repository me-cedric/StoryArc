package app.storyarc.core.format

import app.storyarc.core.model.PublicationFormat
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import kotlin.io.path.createTempDirectory

/**
 * An audiobook becomes a publication rather than a refusal.
 *
 * Every audio container used to reach a **named refusal** at this seam, and the refusal
 * was true while StoryArc could not play audio. This is where it stops being true.
 *
 * `publication-formats`: "it is recognised from its contents as an audiobook and opens in
 * the player rather than in a reader", and "an unchaptered audiobook is a normal
 * audiobook" — so nothing here reports anything as missing. Asserted against the shared
 * corpus. iOS's `AudiobookIndexingTests` asserts the same cases.
 */
class AudiobookIndexingTest {

    @Test
    fun `a chaptered M4B indexes as an audiobook`() = runTest {
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/chaptered.m4b"))
        assertEquals(PublicationFormat.M4B, publication.format)
        assertTrue(publication.format.isAudio)
        assertFalse(publication.format.isPagedImages)
    }

    @Test
    fun `an m4a and an m4b holding the same audio index identically`() = runTest {
        // The scenario, driven rather than reasoned about: the corpus's `.m4a` and its
        // `.m4b` are both MPEG-4, so the extension changes nothing about the format.
        val m4b = PublicationIndexer.index(FixtureCorpus.file("audiobooks/chaptered.m4b"))
        val m4a = PublicationIndexer.index(FixtureCorpus.file("audiobooks/unchaptered.m4a"))
        assertEquals(m4b.format, m4a.format)
    }

    @Test
    fun `an unchaptered audiobook opens and reports nothing missing`() = runTest {
        // "nothing is reported as missing, because an unchaptered audiobook is a normal
        // audiobook". One part standing in for the whole, and no skipped count.
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/unchaptered.m4a"))
        assertEquals(1, publication.pageCount)
        assertEquals(0, publication.skippedPageCount)
        assertFalse(publication.isPartial)
        assertTrue(publication.isOpenable)
    }

    @Test
    fun `an MP3 with ID3 chapters indexes as an audiobook`() = runTest {
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/id3-chapters.mp3"))
        assertEquals(PublicationFormat.MP3, publication.format)
    }

    @Test
    fun `a folder of audio indexes as one audiobook with its parts in order`() = runTest {
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/folder-parts"))
        assertEquals(PublicationFormat.AUDIO_FOLDER, publication.format)
        // Three parts, and the count is the parts rather than a page count of nothing.
        assertEquals(3, publication.pageCount)
    }

    @Test
    fun `a folder mixing audio and images indexes as the kind the majority are`() = runTest {
        // Two audio against one image. `FolderKind` decides; this pins that the indexer
        // *asks* it rather than assuming every folder is a comic, which is what it did.
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/mixed-folder"))
        assertEquals(PublicationFormat.AUDIO_FOLDER, publication.format)
        assertEquals(2, publication.pageCount)
    }

    @Test
    fun `a folder of images is still a comic`() = runTest {
        // The mirror, and the far commoner case: a regression here would turn every
        // unpacked comic into an audiobook. The corpus carries no image folder — both its
        // folders are audiobooks — so this one is built rather than read, and it is the
        // *indexer's* branch that is under test rather than `FolderKind`'s rule.
        val folder = createTempDirectory("image-folder").toFile()
        try {
            File(folder, "page1.png").writeBytes(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47))
            File(folder, "page2.png").writeBytes(byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47))
            File(folder, "theme.mp3").writeBytes(byteArrayOf(0x49, 0x44, 0x33))

            val publication = PublicationIndexer.index(folder)
            assertEquals(PublicationFormat.IMAGE_FOLDER, publication.format)
        } finally {
            folder.deleteRecursively()
        }
    }

    @Test
    fun `a truncated audiobook still opens`() = runTest {
        // `publication-formats`: a damaged audiobook "plays what it can and states how
        // much it could not", by the same rule that opens a comic missing pages. So the
        // index is a publication, never a refusal — what could not be decoded is the
        // player's to state, and it cannot state anything about a book it was not given.
        val publication = PublicationIndexer.index(FixtureCorpus.file("audiobooks/truncated.m4b"))
        assertEquals(PublicationFormat.M4B, publication.format)
        assertTrue(publication.isOpenable)
    }

    @Test
    fun `a protected audiobook is refused for being protected, not for being unsupported`() =
        runTest {
            // The distinction `publication-formats` requires by name: "the refusal is
            // distinct from an unsupported container, because the format itself is
            // supported and this particular file is locked". A shared `Unsupported` would
            // make the app say MPEG-4 is a format it does not read, which is false and
            // sends the reader to convert a file that needs no converting.
            try {
                PublicationIndexer.index(FixtureCorpus.file("audiobooks/protected.aax"))
                fail("a protected audiobook must not index")
            } catch (refusal: IndexException.ContentProtected) {
                assertTrue(refusal.message.orEmpty().isNotBlank())
            } catch (wrong: IndexException.Unsupported) {
                fail("refused as an unsupported container rather than as protected: ${wrong.format}")
            }
        }
}
