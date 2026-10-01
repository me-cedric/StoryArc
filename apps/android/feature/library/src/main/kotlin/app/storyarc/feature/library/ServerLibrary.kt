package app.storyarc.feature.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.smb.SmbClient
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.CredentialStore
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ProgressStore
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
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
     * Every server's rows, with the source each came through, and which sources held back
     * more than they gave.
     *
     * @property rows every publication read, paired with its source.
     * @property partial the sources whose read stopped at its own limit rather than at the
     *   end of the source. [SourceSlice] is where that distinction is explained, and the
     *   source screen is what says it out loud.
     */
    data class Reading(
        val rows: List<Pair<Publication, UUID>> = emptyList(),
        val partial: Set<UUID> = emptySet(),
    )

    /**
     * Every server's slice, in one list, with the source each row came through.
     *
     * Per source and off the main thread, so one slow server does not hold up another or
     * the walk running beside it. A server that throws contributes nothing and costs
     * nothing.
     */
    suspend fun read(
        registry: MutableStateFlow<SourceRegistry>,
        credentials: CredentialStore?,
        pins: CertificatePins,
        progress: ProgressStore? = null,
        kavita: KavitaProgressStore? = null,
    ): Reading = withContext(Dispatchers.IO) {
        val slices = registry.value.sources.map { source ->
            val read = runCatching { slice(source, credentials, pins, progress, kavita) }.getOrNull()
            // **A source that just answered is answering, and the registry says so.**
            //
            // The registry rather than a list, because this read is where the answer is
            // learned and a connection state is never persisted: every source loads as
            // *connecting* and stays there until something says otherwise, and nothing probes
            // on the path a reader takes from the shelf to a publication's page. Measured on
            // an emulator on 2026-09-11 — a catalogue this had just read nine titles from
            // still read *connecting*, so the page said *not answering right now* about a
            // server that had answered a second earlier, while *Your libraries* read
            // *Available* for that same source.
            //
            // Only what came back. A read that threw is not evidence of anything — a feed can
            // fail for a reason that is not the server — so `Unreachable` stays the probe's to
            // give, with the *since* stamp only it can carry. A local folder reads null here
            // and is not a server, so it is not marked either.
            if (read != null) {
                registry.update { it.marking(source.id, SourceConnectionState.Connected) }
            }
            source.id to read.orEmpty()
        }
        Reading(
            rows = slices.flatMap { (id, slice) -> slice.publications.map { it to id } },
            partial = slices.filter { (_, slice) -> slice.holdsMore }.map { it.first }.toSet(),
        )
    }

    /** What one source gives, by the kind of thing it is. */
    private suspend fun slice(
        source: Source,
        credentials: CredentialStore?,
        pins: CertificatePins,
        progress: ProgressStore?,
        kavita: KavitaProgressStore?,
    ): SourceSlice? =
        when (source.kind) {
            SourceKind.KAVITA_SERVER -> KavitaPage.of(source, credentials)?.address?.let { address ->
                val fetched = KavitaContributor.page(source.id, KavitaClient(address), 1)
                // `reading-progress`: "when a synchronising source refreshes, progress
                // recorded on other devices is merged into the local store". This refresh
                // is that moment for every Kavita source, not only the one whose browser
                // the reader happens to have open -- and it also flushes what an earlier,
                // offline session could not send.
                if (progress != null && kavita != null) {
                    KavitaSync.pull(fetched.chapters, kavita, progress, source.id.toString(), address)
                }
                fetched.slice
            }

            SourceKind.OPDS_CATALOG -> CataloguePage.of(source, credentials)
                ?.let { OpdsContributor.publications(source.id, it, pins) }

            SourceKind.NETWORK_SHARE -> SmbPage.of(source, credentials)?.let { page ->
                SmbContributor.publications(
                    source.id,
                    SmbClient(page.address),
                    page.address,
                )
            }

            // Already in the library: its files are what the scan walks.
            SourceKind.LOCAL_FOLDER -> null
        }

    /** A source that refused, or was never configured, gave nothing and held nothing back. */
    private fun SourceSlice?.orEmpty(): SourceSlice = this ?: SourceSlice.none

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
        pins: CertificatePins,
    ): Bitmap? {
        val remote = publication.identity.serverIdentifier ?: return null
        val source = sources.firstOrNull { it.id == remote.sourceId } ?: return null
        return when {
            remote.remoteId.startsWith(CHAPTER) -> kavitaCover(remote.remoteId, source, credentials)
            remote.remoteId.startsWith(OPDS) -> opdsCover(remote.remoteId, source, credentials, pins)
            else -> null
        }
    }

    private suspend fun kavitaCover(remoteId: String, source: Source, credentials: CredentialStore?): Bitmap? {
        val chapter = remoteId.removePrefix(CHAPTER).toIntOrNull() ?: return null
        val address = KavitaPage.of(source, credentials)?.address ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                val bytes = KavitaClient(address).chapterCover(chapter)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }.getOrNull()
        }
    }

    /**
     * An OPDS row's artwork, fetched through the catalogue it came from. [OpdsContributor]
     * keeps no acquisition address -- such a link can carry a key in its query -- so the
     * entry is found again by the id the row was filed under, through the origin-bound
     * client [OpdsContributor.client] already builds. 11.7 / D29: an unreachable catalogue
     * answers nothing here, same as it answers nothing to the read that fills the shelf.
     */
    private suspend fun opdsCover(
        remoteId: String,
        source: Source,
        credentials: CredentialStore?,
        pins: CertificatePins,
    ): Bitmap? = withContext(Dispatchers.IO) {
        runCatching {
            val page = CataloguePage.of(source, credentials) ?: return@runCatching null
            val client = OpdsContributor.client(page, pins)
            val feed = client.feed(page.url, page.credential)
            val url = feed.publications.firstOrNull { "opds:${it.id}" == remoteId }
                ?.let { it.thumbnail ?: it.cover }
                ?: return@runCatching null
            val bytes = client.bytes(url, page.credential)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull()
    }

    /** What a chapter's remote id is prefixed with. See [KavitaContributor.publication]. */
    const val CHAPTER = "chapter:"

    /** What an OPDS row's remote id is prefixed with. See [OpdsContributor.publication]. */
    const val OPDS = "opds:"

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
        pins: CertificatePins,
        into: MutableMap<String, Bitmap>,
        store: (Bitmap) -> Unit,
    ): Bitmap? = cover(publication, sources, credentials, pins)?.also {
        store(it)
        into[publication.id] = it
    }
}
