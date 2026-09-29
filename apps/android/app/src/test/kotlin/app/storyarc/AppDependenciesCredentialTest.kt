package app.storyarc

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.SourceStore
import java.util.UUID
import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A transfer's credential is refused unless the record's own source is configured at the
 * address the record is about to be fetched from.
 *
 * dl-core 1.1: a queue kept per catalogue refused a credential to any address but the one
 * its own `origin` named. A shared queue has no one `origin`, so `DownloadQueue`'s own
 * `home?.admits(url)` check now compares a value against itself and is never false --
 * `AppDependencies.sourceEligibleForCredential` is where the promise moves instead, and it
 * is asked here directly: the platform Keystore behind `credentialFor` only a device or an
 * emulator can open. iOS asserts the same two claims in `DownloadQueueSharedTests`'
 * `credentialRefusedForMismatchedOrigin` and `credentialResolvedForMatchingOrigin`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppDependenciesCredentialTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun seed(sourceId: UUID, remote: String) {
        DownloadStore.open(context).reset()
        DownloadStore.open(context).save(
            DownloadLibrary(
                downloads = listOf(
                    Download(
                        id = "book-1",
                        sourceId = sourceId,
                        title = "Book",
                        remote = remote,
                        mediaType = "application/epub+zip",
                    ),
                ),
            ),
        )
        SourceStore.open(context).save(
            SourceRegistry(
                sources = listOf(
                    Source(
                        id = sourceId,
                        displayName = "Library",
                        kind = SourceKind.OPDS_CATALOG,
                        credentialReference = "ref-$sourceId",
                        locator = "https://library.example",
                    ),
                ),
            ),
        )
    }

    @Test
    fun `refused when the record's source is not configured at that address`() {
        val dependencies = AppDependencies.open(context)
        val sourceId = UUID.randomUUID()
        // The download's own address is a different origin from the source it is filed
        // under -- a redirect, or a record built before the source's address changed.
        seed(sourceId, remote = "https://elsewhere.invalid/book.epub")

        assertNull(
            "The credential would have travelled to an address the source was never " +
                "configured at.",
            dependencies.sourceEligibleForCredential("book-1"),
        )
    }

    @Test
    fun `resolved when the record's source is configured at that address`() {
        val dependencies = AppDependencies.open(context)
        val sourceId = UUID.randomUUID()
        seed(sourceId, remote = "https://library.example/book.epub")

        assertEquals(sourceId, dependencies.sourceEligibleForCredential("book-1")?.id)
    }
}
