package app.storyarc.feature.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.Download
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import java.io.File

/**
 * The copy a library row can obtain, and how far it has come.
 *
 * `publication-detail`'s *No copy on the device and a library that answers*: the page's
 * primary action "is to obtain the copy", and *Downloading from here* requires that copy to
 * join "the same queue as every other download" so that "the transfer continues after the
 * reader leaves the page". [DownloadQueue] is that queue. It is the only route that honours
 * the Wi-Fi-only and Data-Saver rules, and the only one that starts [DownloadService]; the
 * page's former route read the whole file in one foreground call, so the transfer died with
 * the process and nothing on the page ever said so.
 *
 * A value rather than three parameters on the page, because the three answers are one
 * answer: a row that can be fetched has a [start], a row being fetched has a [record], and a
 * row already fetched has a [file]. A row with no route at all is the default instance, which
 * is what every non-catalogue publication gets -- an SMB share keeps its own copy route,
 * because [OpdsClient] refuses any scheme that is not http or https.
 */
internal data class PublicationCopy(
    /**
     * The queue's own record for this row, for the progress and the wait the page states.
     *
     * Read by the *entry* id, never by [Publication.id]: [DownloadQueue.enqueue] files a
     * download under the catalogue entry's id, and the row's stable id is
     * `srv:<source>:opds:<entry>`. A page that looked itself up by [Publication.id] found
     * nothing, showed no progress, and never noticed the copy arriving.
     */
    val record: Download? = null,
    /** The finished copy on disk, which is the only address the page may open. */
    val file: File? = null,
    /** Queues the copy, asking about mobile data first. Null when there is nothing to take. */
    val start: (() -> Unit)? = null,
)

/**
 * Which acquisition to take for a row the reader is looking at.
 *
 * [CatalogueAcquisition.best] answers a different question -- which format this app would
 * *prefer* -- and the two answers differ for a real feed. A library row is filed under the
 * first media type the entry declares that this app can read (`OpdsContributor.publication`),
 * while `best` ranks EPUB, then the comic containers, then PDF. An entry offering PDF before
 * CBZ is therefore a PDF row whose download would arrive as a CBZ, and the row's format,
 * its cover fit and its reading direction would all then describe a file the reader does not
 * have. The format the page names is the format the page fetches.
 *
 * The fallback is `best`, for the entry that no longer offers what the row was filed under:
 * a catalogue may drop a format between two reads, and the readable copy that remains is a
 * better answer than a refusal.
 *
 * Null when the entry offers nothing this app can fetch -- a borrow or a purchase flow, which
 * `opds-catalog` requires to be stated rather than attempted. The page then offers no copy,
 * which is the honest answer and not a button that fails when it is pressed.
 *
 * Pure, and separately named so it is tested without a Context, a queue or a network.
 */
internal fun acquisitionFor(publication: Publication, entry: OpdsEntry): OpdsAcquisition? {
    val readable = CatalogueAcquisition.readable(entry)
    return readable.firstOrNull { PublicationFormat.ofMediaType(it.mediaType) == publication.format }
        ?: readable.firstOrNull()
}

/**
 * The copy route for one library row, and the mobile-data question that route has to ask.
 *
 * **Why the feed is read again.** `OpdsContributor`'s rule is that no acquisition URL is
 * kept: such a link can carry a key in its query, and `sources` forbids a cached catalogue
 * holding a credential. The row keeps the entry's id, so the address is asked for again where
 * the credential is still in hand. One request finds it every time, because the contributor
 * reads exactly one page of exactly this URL, so every OPDS row is an entry of it. The match
 * is on the whole `opds:` id, so a row from some other kind of source resolves to nothing
 * rather than to the wrong publication.
 *
 * **Why this draws the dialog.** [MeteredConfirmation] is internal to this module while the
 * source registry and the credential store are not, so the wording cannot be raised from the
 * app layer. It is also the same state as the enqueue it guards: the ask carries the entry and
 * the acquisition, and the confirm repeats the enqueue with the grant, exactly as
 * `CatalogueDetailScreen` already does. `offline-downloads` grants the override "for that item
 * only", which is why it travels with the call.
 *
 * **Why [DownloadQueue.enqueue] and never `fetch`.** `fetch` parks a waiter on the transfer
 * for a caller that means to open it now, and a queue held for Wi-Fi leaves that waiter with
 * nothing to wake it. The page does not need to wait: it watches [DownloadQueue.library] and
 * the primary action becomes the read when the copy lands.
 *
 * [start] stays offered while a transfer runs, because `DownloadLibrary.queueing` ignores an
 * id it already holds. A second press is therefore harmless, and the page decides what it
 * draws from [record].
 */
@Composable
internal fun rememberPublicationCopy(
    publication: Publication,
    page: CataloguePage?,
    queue: DownloadQueue?,
): PublicationCopy {
    if (page == null || queue == null) return PublicationCopy()
    val remoteId = publication.identity.serverIdentifier?.remoteId ?: return PublicationCopy()

    var entry by remember(publication.id) { mutableStateOf<OpdsEntry?>(null) }
    var meteredAsk by remember(publication.id) { mutableStateOf<MeteredAsk?>(null) }
    val downloads by queue.library.collectAsStateWithLifecycle()

    LaunchedEffect(publication.id) {
        // A catalogue that has gone away is not an error the page reports: the row is still
        // in the library, `PublicationProvenance` already says the source is unreachable, and
        // this only decides whether a copy can be offered.
        entry = runCatching { catalogueEntry(page, remoteId) }.getOrNull()
    }

    val found = entry
    val acquisition = found?.let { acquisitionFor(publication, it) }

    val record = found?.let { downloads[it.id] }

    /**
     * Queues the copy, and moves a record the store already holds back into the queue.
     *
     * **The second half is not belt and braces.** [DownloadLibrary.queueing] keeps the record
     * it already has for an id and ignores the new one, so `enqueue` alone does nothing at all
     * for a publication that was tried before and left a `Failed` record, or one whose source
     * was removed and re-added. Photographed on a phone: the page drew *Download it*, the tap
     * queued nothing, and no transfer began -- which is the exact failure this whole change
     * exists to abolish, arriving by a different route.
     *
     * [DownloadQueue.resume] rather than cancel and re-queue, because a held or failed row
     * keeps the bytes it already has and `resume` is the verb that keeps them.
     */
    fun begin(overridingMeteredConnection: Boolean) {
        queue.enqueue(
            found ?: return,
            acquisition ?: return,
            overridingMeteredConnection = overridingMeteredConnection,
            sourceId = publication.sourceId,
        )
        val held = record?.state?.let { !it.isActive && !it.isFinished } == true
        if (held) queue.resume(found.id)
    }

    MeteredConfirmation(
        ask = meteredAsk,
        onDismiss = { meteredAsk = null },
        // Through [begin] rather than straight to `enqueue`, so a grant given for a
        // publication whose record the store already holds restarts it rather than being
        // recorded against a row nothing moves.
        onConfirm = {
            meteredAsk = null
            begin(overridingMeteredConnection = true)
        },
    )

    val start: (() -> Unit)? = if (found != null && acquisition != null) {
        {
            if (queue.needsMeteredConfirmation(found)) {
                meteredAsk = MeteredAsk(found, acquisition, queue.statedBytes(found))
            } else {
                begin(overridingMeteredConnection = false)
            }
        }
    } else {
        null
    }

    return PublicationCopy(
        record = record,
        // Asked of the queue only when the record says the bytes are all there, because the
        // answer touches the filesystem: a copy the system reclaimed is not a copy, and
        // `downloaded` is the call that knows it.
        file = remember(found?.id, record?.state) {
            found?.takeIf { record?.state?.isFinished == true }?.let(queue::downloaded)
        },
        start = start,
    )
}

/**
 * The catalogue entry behind one library row, or null when the feed no longer lists it.
 *
 * Built the same way the contributor builds it -- `OpdsClient(origin = page.origin)`, no pins
 * -- so the page and the library read the same catalogue the same way. A catalogue behind
 * a pinned certificate already fails the library read, and pinning it here alone would make
 * the page succeed where the row it is showing could not exist.
 */
private suspend fun catalogueEntry(page: CataloguePage, remoteId: String): OpdsEntry? =
    OpdsClient(origin = page.origin)
        .feed(page.url, page.credential)
        .publications
        .firstOrNull { "opds:${it.id}" == remoteId }
