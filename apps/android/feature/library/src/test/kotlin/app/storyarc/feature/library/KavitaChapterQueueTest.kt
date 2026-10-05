package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.DownloadStore
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A kept Kavita chapter is a download like any other -- `offline-downloads` 1.9.
 *
 * It was not. `KavitaKeep` read the whole body into memory, wrote it to a cache file and moved
 * it into the download store itself, so the chapter had no row in the downloads view and none
 * of the pause, resume, retry or concurrency bound *Queue management* asks for.
 *
 * Two claims, and the second is the one the ordering problem turns on: the destination's
 * extension is chosen from the record, Kavita states the type only in the response, and an
 * EPUB written under `.cbz` reaches the comic reader. iOS asserts the same two in
 * `KavitaChapterQueueTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaChapterQueueTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val chapterId = "kavita:4F1B0C7E-0000-0000-0000-00000000ABCD:3103"

    private val remote = "https://kavita.invalid/api/Download/chapter?chapterId=3103"

    private fun queue(store: DownloadStore) = DownloadQueue(
        context,
        CertificatePins(),
        store,
        settings = { AppSettings(downloadOverWifiOnly = false) },
        onWifi = MutableStateFlow(true),
    )

    private fun chapter(mediaType: String = "") = Download(
        id = chapterId,
        title = "Harbour Lights 03",
        remote = remote,
        mediaType = mediaType,
    )

    /**
     * One real EPUB from the shared corpus, which is the only thing that can answer "what are
     * these bytes" honestly. `core:format`'s own `FixtureCorpus` is not on this module's test
     * path, so the walk-up it falls back to is repeated here.
     */
    private val epubFixture: File
        get() {
            var directory: File? = File("").absoluteFile
            while (directory != null) {
                val corpus = File(directory, "packages/test-fixtures")
                if (File(corpus, "manifest.json").isFile) return File(corpus, "ebooks/declared-rtl.epub")
                directory = directory.parentFile
            }
            error("fixture corpus not found above ${File("").absolutePath}")
        }

    @Test
    fun `a chapter the reader keeps becomes a record the queue owns`() {
        val queue = queue(DownloadStore.open(context))

        CoroutineScope(Dispatchers.Unconfined).launch {
            queue.fetchChapter(
                id = chapterId,
                title = "Harbour Lights 03",
                remote = remote,
                sourceId = null,
                credential = OpdsCredential.Bearer("session-token"),
                seriesHint = "Harbour Lights",
            )
        }

        val record = queue.library.value[chapterId]
        assertNotNull(record)
        assertEquals("Harbour Lights 03", record?.title)
        // Nothing guessed. The server names the type in the response, and the record says so
        // by saying nothing until it has one.
        assertEquals("", record?.mediaType)
        assertEquals(OpdsCredential.Bearer("session-token"), queue.given[chapterId])
    }

    @Test
    fun `a landed chapter is named from its bytes when the record names no format`() = runBlocking {
        val store = DownloadStore.open(context)
        val queue = queue(store)
        val download = chapter()
        queue.record(download)

        // What a guess would have written: a media type naming no format implies no extension.
        assertEquals("bin", store.location(download).extension)

        val typed = queue.typed(download, epubFixture)

        assertEquals("epub", store.location(typed).extension)
        assertEquals("application/epub+zip", queue.library.value[chapterId]?.mediaType)
    }

    @Test
    fun `a record that already names a format is left exactly as it is`() = runBlocking {
        val queue = queue(DownloadStore.open(context))
        val download = chapter(mediaType = "application/vnd.comicbook+zip")
        queue.record(download)

        // The bytes are an EPUB and the record says CBZ, and this still does not overrule it:
        // an OPDS acquisition link states its own type and is the authority on it.
        assertEquals(download, queue.typed(download, epubFixture))
    }

    @Test
    fun `a chapter already on the device is handed back without a second transfer`() = runBlocking {
        val store = DownloadStore.open(context)
        val queue = queue(store)
        val finished = chapter(mediaType = "application/epub+zip").copy(state = Download.State.Finished)
        queue.record(finished)
        val landed = store.location(finished)
        landed.parentFile?.mkdirs()
        epubFixture.copyTo(landed, overwrite = true)

        assertEquals(
            landed,
            queue.fetchChapter(
                id = chapterId,
                title = "Harbour Lights 03",
                remote = remote,
                sourceId = null,
                credential = OpdsCredential.Bearer("session-token"),
            ),
        )
    }
}
