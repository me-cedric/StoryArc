package app.storyarc.feature.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * What the configured servers put in the library, and how a row with no file is drawn.
 *
 * `library-browsing` requires one library over every source -- "publications from every
 * configured source are shown together". A folder walk cannot reach a server, so this is
 * the other half of the answer, and it lives beside the view model rather than inside it
 * because that file is already over its line cap.
 *
 * **Nothing here ever removes a row.** [ScanReconciliation] deletes only from a source
 * whose own round covered it, and a server is in no round, so a server that refuses or
 * answers nothing costs a reader nothing. `sources` asks for exactly that -- "a failed
 * refresh and an emptied source are different things" -- and it holds by construction.
 */
internal object ServerLibrary {

    /**
     * Every server's slice, in one list, with the source each row came through.
     *
     * Per source and off the main thread, so one slow server does not hold up another or
     * the walk running beside it. A server that throws contributes nothing and costs
     * nothing.
     */
    suspend fun read(
        sources: List<Source>,
        credentials: CredentialStore?,
    ): List<Pair<Publication, UUID>> = withContext(Dispatchers.IO) {
        sources.flatMap { source ->
            runCatching {
                when (source.kind) {
                    SourceKind.KAVITA_SERVER -> KavitaPage.of(source, credentials)?.address
                        ?.let { KavitaContributor.publications(source.id, KavitaClient(it)) }

                    SourceKind.OPDS_CATALOG -> CataloguePage.of(source, credentials)
                        ?.let { OpdsContributor.publications(source.id, it) }

                    // A share is a filesystem, and a filesystem is walked rather than
                    // asked. `local-library`'s scan already knows how; what it does not
                    // have is an incremental index for a tree it reaches over a network,
                    // and a blind walk of a share is unbounded. Named here rather than
                    // silently skipped.
                    SourceKind.NETWORK_SHARE -> null

                    // Already in the library: its files are what the scan walks.
                    SourceKind.LOCAL_FOLDER -> null
                }
            }.getOrNull().orEmpty().map { it to source.id }
        }
    }

    /**
     * A cover for a row with nothing on disk.
     *
     * Every cover before this one came out of the publication's own file, so a row a
     * server supplied had none: the library has no location for it and the resolver
     * returned null. The server is asked instead, through the client rather than an image
     * loader, because Kavita's image routes want the reader's key and a loader has nowhere
     * to put one.
     */
    suspend fun cover(
        publication: Publication,
        sources: List<Source>,
        credentials: CredentialStore?,
    ): Bitmap? {
        val remote = publication.identity.serverIdentifier ?: return null
        val chapter = remote.remoteId.removePrefix(CHAPTER).toIntOrNull() ?: return null
        val source = sources.firstOrNull { it.id == remote.sourceId } ?: return null
        val address = KavitaPage.of(source, credentials)?.address ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val bytes = KavitaClient(address).chapterCover(chapter)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
    }

    /** What a chapter's remote id is prefixed with. See [KavitaContributor.publication]. */
    const val CHAPTER = "chapter:"

    /**
     * [cover], plus the caching every other cover in the library already gets.
     *
     * Here rather than in the view model because that file is over its line cap and may
     * not grow: the rule is in `scripts/line-cap.mjs`, and paying for a new feature by
     * deleting an existing explanation would be the wrong way to satisfy it.
     */
    suspend fun cachedCover(
        publication: Publication,
        sources: List<Source>,
        credentials: CredentialStore?,
        into: MutableMap<String, Bitmap>,
        store: (Bitmap) -> Unit,
    ): Bitmap? = cover(publication, sources, credentials)?.also {
        store(it)
        into[publication.id] = it
    }
}
