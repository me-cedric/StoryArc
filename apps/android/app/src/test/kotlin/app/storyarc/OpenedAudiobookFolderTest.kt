package app.storyarc

import android.net.Uri
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.playback.PartLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import kotlin.io.path.createTempDirectory

/**
 * Task 28.8: a folder that holds one chaptered file keeps its chapters.
 *
 * Each download lives in a folder of its own, so a downloaded M4B arrives as a folder of one
 * file. The folder's one part becomes the book's one source, and a one-source book takes the
 * [PartLayout.MARKS] layout: the page reads the file's chapter marks through
 * `ChapterMarks.parts`, and the player adopts them when the tracks arrive. A folder of several
 * files keeps one part per file. `ChapterMarksInstrumentedTest` proves the marks of
 * `chaptered.m4b` themselves on a device; iOS's `AudiobookReaderTests` makes the same claim.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class OpenedAudiobookFolderTest {

    private fun corpus(relative: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "packages/test-fixtures/$relative")
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        error("fixture corpus not found above ${File("").absolutePath} -- expected packages/test-fixtures")
    }

    private fun folderBook(folder: File) = Publication(
        identity = PublicationIdentity(normalizedPath = folder.path),
        format = PublicationFormat.AUDIO_FOLDER,
        displayTitle = "Sea Room",
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `a folder of one file plays as that file, with its own chapter marks`() {
        val folder = createTempDirectory("one-file").toFile()
        val file = corpus("audiobooks/chaptered.m4b").copyTo(File(folder, "sea-room.m4b"))

        val book = requireNotNull(OpenedAudiobook.of(folderBook(folder), folder.path))

        assertEquals(PartLayout.MARKS, book.layout)
        assertEquals(listOf(Uri.fromFile(file).toString()), book.sources.map { it.uri })
        folder.deleteRecursively()
    }

    @Test
    fun `a folder of several files keeps one part per file`() {
        val book = requireNotNull(OpenedAudiobook.of(folderBook(corpus("audiobooks/folder-parts")), corpus("audiobooks/folder-parts").path))

        assertEquals(PartLayout.FILES, book.layout)
        assertEquals(listOf("Part1", "Part2", "Part10"), book.sources.map { it.title })
        assertTrue(book.sources.all { it.uri.startsWith("file://") })
    }
}
