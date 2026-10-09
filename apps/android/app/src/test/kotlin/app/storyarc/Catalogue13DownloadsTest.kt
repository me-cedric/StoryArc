package app.storyarc

import android.app.Application
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Download
import app.storyarc.core.snapshots.CATALOGUE_QUALIFIERS
import app.storyarc.core.snapshots.Fixtures
import app.storyarc.core.snapshots.Look
import app.storyarc.core.snapshots.brandAccentText
import app.storyarc.core.snapshots.dangerText
import app.storyarc.core.snapshots.catalogue
import app.storyarc.feature.library.LibraryViewModel
import app.storyarc.feature.library.adoptDownloads
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Catalogue entry 13: the Downloads destination, with two transfers that are not running and
 * three finished downloads on the shelf.
 *
 * The transfers are paused by the reader and failed, never queued or running, so no test run
 * starts one and the picture does not change under it. The finished downloads are real archives
 * in the downloads folder, adopted by the library the way the app adopts them.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = CATALOGUE_QUALIFIERS)
class Catalogue13DownloadsTest {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val application: Application = ApplicationProvider.getApplicationContext()

    private val finished = listOf("Harbour Lights 01", "Harbour Lights 02", "Tin Kingdom")

    private fun host(): AppHost {
        val dependencies = AppDependencies.open(application)
        val store = dependencies.downloads
        val finishedDownloads = finished.mapIndexed { index, title ->
            Download(
                id = "finished-$index",
                title = title,
                remote = "https://example.invalid/$index.cbz",
                mediaType = "application/vnd.comicbook+zip",
                state = Download.State.Finished,
                expectedBytes = 4_000_000,
                downloadedBytes = 4_000_000,
            )
        }
        finishedDownloads.forEachIndexed { index, download ->
            val file = store.location(download)
            store.prepare(file)
            ZipOutputStream(FileOutputStream(file)).use { zip ->
                zip.putNextEntry(ZipEntry("page-01.png"))
                Fixtures.cover(index, 400, 600).compress(Bitmap.CompressFormat.PNG, 90, zip)
                zip.closeEntry()
            }
        }
        val transfers = listOf(
            Download(
                id = "paused",
                title = "Salt Road 04",
                remote = "https://example.invalid/salt.cbz",
                mediaType = "application/vnd.comicbook+zip",
                state = Download.State.Paused(Download.Pause.BY_READER),
                expectedBytes = 80_000_000,
                downloadedBytes = 31_000_000,
            ),
            Download(
                id = "failed",
                title = "Night Ferry",
                remote = "https://example.invalid/ferry.epub",
                mediaType = "application/epub+zip",
                state = Download.State.Failed("The server did not answer.", attempts = 3),
                expectedBytes = 12_000_000,
                downloadedBytes = 0,
            ),
        )
        store.save(app.storyarc.core.model.DownloadLibrary(transfers + finishedDownloads))

        val library = LibraryViewModel(application, downloadStore = store)
        library.adoptDownloads()
        return AppHost(
            activity = compose.activity,
            dependencies = dependencies,
            library = library,
            downloads = mutableStateOf(store.library()),
            removed = mutableStateOf(null),
            navigate = {},
            open = { _, _ -> },
            openPage = {},
            browse = { _, _ -> },
            sheet = {},
            isReading = { false },
        )
    }

    private fun draw(look: Look) {
        val host = host()
        compose.catalogue(
            "13-downloads",
            look,
            // Accent and error text, listed for the reason `brandAccentText` and `dangerText` give.
            listOf(
                brandAccentText("Pause all"),
                brandAccentText("Resume all"),
                brandAccentText("Cancel all"),
                brandAccentText("Resume", Look.Dark),
                brandAccentText("Retry", Look.Dark),
                dangerText("Remove download", Look.Dark),
                dangerText("Failed after 3 attempts"),
            ),
            act = {
                waitUntil(timeoutMillis = 10_000) { host.library.publications.value.size == finished.size }
                // Covers decode off the main thread: the well that says CBZ goes when they land.
                waitUntil(timeoutMillis = 10_000) {
                    onAllNodesWithText("CBZ", useUnmergedTree = true).fetchSemanticsNodes().isEmpty()
                }
            },
        ) { DownloadsDestination(host) }
    }

    @Test
    fun light() = draw(Look.Light)

    @Test
    fun dark() = draw(Look.Dark)
}
