package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import app.storyarc.core.catalogue.CoverLookupCache
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.catalogue.CoverTransport
import app.storyarc.core.catalogue.PlatformCoverTransport
import app.storyarc.core.format.PageDecoder
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.SettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The last rung of the cover ladder: ask an open catalogue, only when the reader said it may.
 *
 * Task 6.1 of `cover-for-every-publication`. Beside [LibraryViewModel] for the reason
 * `LibraryViewModelCoverChoice.kt` is: that file is at its line cap. iOS's `CoverLookupRung`
 * is its twin.
 *
 * Three trust rules hold here and in [CoverLookupClient], and each is asserted by a test:
 * the setting is read at the moment of use and nothing is read or asked while it is off, the
 * request carries one identifier and nothing else, and the client reaches only the hosts the
 * setting names and reads at most 8 MB of an answer.
 */
internal class CoverLookupRung(
    private val isEnabled: () -> Boolean,
    private val client: CoverLookupClient,
    private val identify: suspend (Publication) -> CoverIdentifier?,
) {
    /**
     * The picture a catalogue holds for this publication, or null.
     *
     * The gate comes before the identifier is read, so a reader with the lookup off costs
     * the file no extra read at all. The publication's id keys the cache; it never travels.
     */
    suspend fun picture(publication: Publication): ByteArray? {
        if (!isEnabled()) return null
        val identifier = identify(publication) ?: return null
        return client.coverImage(publication.id, identifier)
    }
}

/** The one client and cache of the process, so two callers never keep two copies of one file. */
internal object CoverLookup {
    private var shared: CoverLookupClient? = null

    /** What the client sends through. A test swaps it to count what would leave the device. */
    @Volatile
    internal var transport: CoverTransport = PlatformCoverTransport

    /** Forgets the client, so the next one is built with the current [transport]. */
    internal fun reset() = synchronized(this) { shared = null }

    fun client(app: Application): CoverLookupClient = synchronized(this) {
        shared ?: CoverLookupClient(
            isEnabled = { lookUpIsOn(app) },
            cache = CoverLookupCache.inDataDirectory(app.filesDir),
            transport = transport,
        ).also { shared = it }
    }

    fun lookUpIsOn(app: Application): Boolean =
        SettingsStore.open(app).settings().lookUpMissingCovers
}

/**
 * The cover from the rungs that need the file, then the lookup.
 *
 * The one call [LibraryViewModel.cover] makes below its caches, so a looked-up picture is
 * stored by the same line that stores any other.
 */
internal suspend fun LibraryViewModel.ladderCover(
    publication: Publication,
    path: String,
    maxPixelSize: Int,
): Bitmap? = coverLadder.cover(resolver, publication, path, maxPixelSize)
    ?: lookedUpCover(publication, path, maxPixelSize)

private suspend fun LibraryViewModel.lookedUpCover(
    publication: Publication,
    path: String,
    maxPixelSize: Int,
): Bitmap? {
    val app = getApplication<Application>()
    val rung = CoverLookupRung(
        isEnabled = { CoverLookup.lookUpIsOn(app) },
        client = CoverLookup.client(app),
        identify = { PublicationAccess.identifier(resolver, it, path) },
    )
    val picture = rung.picture(publication) ?: return null
    return withContext(Dispatchers.IO) {
        runCatching { PageDecoder.decode(picture, maxPixelSize) }.getOrNull()
    }
}
