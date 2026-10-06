package app.storyarc.core.format

import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Task 1.1: an audiobook picked through the Storage Access Framework gets its own artwork.
 *
 * Task 16.9 of `close-the-audited-gaps` read embedded artwork at index time and left exactly
 * this open: "it is open where Android indexes audio through SAF, because neither the
 * single-file nor the folder SAF path can reach a file to read". The single-file path can —
 * [UriSource] holds an open `ParcelFileDescriptor`, whose `/proc/self/fd/N` is a path
 * `MediaMetadataRetriever` accepts — and all that was missing was somewhere to write the
 * bytes to. So a reader who picked their audiobooks with the system folder picker, which is
 * the only way to reach a shared folder on modern Android, saw a glyph for every book even
 * where the file carried its own picture.
 *
 * Instrumented, for [AudiobookCoverInstrumentedTest]'s reason doubled: `MediaMetadataRetriever`
 * is a stub on a host JVM, and a content `Uri` needs a real provider on the other end.
 * `FileProvider` hands back the same kind of descriptor a document tree does.
 *
 * The *folder* half of the same task is `SafLooseCoverTest`, which needs neither.
 */
@RunWith(AndroidJUnit4::class)
class SafAudiobookCoverInstrumentedTest {

    private val context = InstrumentationRegistry.getInstrumentation().context
    private val resolver get() = context.contentResolver

    @Test
    fun indexingAnM4bThroughAContentUriWritesItsCoverAndRecordsThePath(): Unit = runBlocking {
        val directory = directory("saf-audiobook-cover")
        val file = fixture("audiobooks/with-cover.m4b")

        val publication = UriSource(resolver, uriFor(file)).use { source ->
            PublicationIndexer.index(
                source = source,
                name = file.name,
                identity = app.storyarc.core.model.PublicationIdentity(
                    normalizedPath = uriFor(file).toString(),
                ),
                coverCacheDir = directory,
            )
        }

        val path = publication.coverPath
        assertNotNull("a picked audiobook with a covr atom records where its cover went", path)
        assertTrue(File(path!!).isFile)
        assertTrue(File(path).readBytes().isNotEmpty())
        directory.deleteRecursively()
    }

    @Test
    fun aPickedAudiobookWithNoArtworkRecordsNothing(): Unit = runBlocking {
        val directory = directory("saf-audiobook-no-cover")
        val file = fixture("audiobooks/chaptered.m4b")

        val publication = UriSource(resolver, uriFor(file)).use { source ->
            PublicationIndexer.index(
                source = source,
                name = file.name,
                identity = app.storyarc.core.model.PublicationIdentity(
                    normalizedPath = uriFor(file).toString(),
                ),
                coverCacheDir = directory,
            )
        }

        assertNull(publication.coverPath)
        directory.deleteRecursively()
    }

    private fun directory(name: String) =
        File(context.cacheDir, name).also { it.deleteRecursively() }

    private fun fixture(name: String): File {
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    private fun uriFor(file: File) =
        FileProvider.getUriForFile(context, "app.storyarc.core.format.test", file)
}
