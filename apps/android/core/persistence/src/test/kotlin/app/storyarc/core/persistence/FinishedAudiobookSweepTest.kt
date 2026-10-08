package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `audiobooks-and-playback` task 7.3: a finished audiobook reaches the sweep.
 *
 * The player writes a listening record for the book's own file, and the sweep in `AppIntents`
 * asks the progress store about each finished download by that file's path. Nothing had put the
 * two together for an audiobook, so this drives them as the app does: a real store, a record
 * the way `PlayingBook` writes one, and the question the sweep asks.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class FinishedAudiobookSweepTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())

    private fun store(): DownloadStore = DownloadStore(FakePreferences(), folder.newFolder("downloads"))

    private fun audiobookIn(store: DownloadStore): DownloadLibrary {
        val download = Download(
            id = "sea-room",
            title = "Sea Room",
            remote = "https://example.test/sea-room",
            mediaType = "audio/mp4",
            state = Download.State.Finished,
            downloadedBytes = 3,
        )
        val file = store.location(download)
        store.prepare(file)
        file.writeBytes(byteArrayOf(1, 2, 3))
        return DownloadLibrary(downloads = listOf(download))
    }

    private fun heard(store: DownloadStore, library: DownloadLibrary, isFinished: Boolean) = runBlocking {
        val path = store.location(library.downloads.single()).absolutePath
        progress.save(
            ReadingProgress(
                identity = PublicationIdentity(normalizedPath = path),
                position = ReadingPosition.Listening(part = 2, partCount = 3, offsetMillis = 60_000, ofMillis = 60_000),
                isFinished = isFinished,
                updatedAtEpochMillis = 1L,
            ),
        )
    }

    /** The question `ForgetFinishedDownloads` asks. */
    private fun swept(store: DownloadStore, library: DownloadLibrary): Download? = runBlocking {
        finishedDownload(store, library, progress)
    }

    @Test
    fun `a listening record that is finished sweeps the audiobook's download`() {
        val store = store()
        val library = audiobookIn(store)
        heard(store, library, isFinished = true)

        assertEquals("sea-room", swept(store, library)?.id)
    }

    @Test
    fun `a listening record that is not finished leaves the download alone`() {
        val store = store()
        val library = audiobookIn(store)
        heard(store, library, isFinished = false)

        assertNull(swept(store, library))
    }

    @Test
    fun `a book nobody listened to is not swept`() {
        val store = store()

        assertNull(swept(store, audiobookIn(store)))
    }
}
