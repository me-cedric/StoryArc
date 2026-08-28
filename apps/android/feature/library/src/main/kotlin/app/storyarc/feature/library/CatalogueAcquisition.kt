package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.persistence.DownloadStore
import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/**
 * Fetching a publication a catalogue offers, and making it something the reader can open.
 *
 * `opds-catalog`'s third requirement. A catalogue entry is not a publication: it is a
 * promise of one, in one or more formats, some of which this app cannot read. This is what
 * turns the promise into a file.
 *
 * The file is a download, not a cache entry. It lands in `files/downloads`, which the backup
 * rules already exclude, it is recorded so it can be listed and removed, and it is verified
 * before it is called finished. What is still missing from `offline-downloads` is the queue:
 * this fetches one publication at a time, in the foreground, with no pause and no resume.
 */
class CatalogueAcquisition(
    private val context: Context,
    pins: CertificatePins,
    private val store: DownloadStore? = null,
) {
    sealed interface State {
        data object Idle : State
        data class Fetching(val title: String) : State
        data class Failed(val message: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    private val client = OpdsClient(pins)

    private val _library = MutableStateFlow(store?.library() ?: DownloadLibrary())

    /** What has been downloaded, published so the grid can show it. */
    val library: StateFlow<DownloadLibrary> = _library.asStateFlow()

    /**
     * Where a publication already downloaded lives, if it does.
     *
     * `offline-downloads`: when a publication is already downloaded "the download action is
     * replaced by a state indicator and a remove-download action, and the app does not
     * re-fetch it". Asked of the filesystem, not of the record: a download the system
     * reclaimed is one the reader should be offered again rather than shown a missing file.
     */
    fun downloaded(entry: OpdsEntry): File? {
        val download = _library.value[entry.id]?.takeIf { it.state.isFinished } ?: return null
        val file = store?.location(entry.id, extensionOf(download.mediaType)) ?: return null
        return file.takeIf { it.exists() }
    }

    /** Forgets a download and deletes its file. */
    fun remove(id: String) {
        _library.value[id]?.let { download ->
            store?.let { it.delete(it.location(id, extensionOf(download.mediaType))) }
        }
        _library.value = _library.value.removing(id)
        store?.save(_library.value)
    }

    private fun extensionOf(mediaType: String): String =
        PublicationFormat.ofMediaType(mediaType)?.name?.lowercase() ?: "bin"

    /**
     * Fetches one acquisition and indexes it.
     *
     * Returns the publication and where it landed, which is exactly what the library hands
     * to a reader. Null when anything went wrong, with [state] saying what.
     */
    suspend fun fetch(
        entry: OpdsEntry,
        link: OpdsAcquisition,
        credential: OpdsCredential?,
    ): Pair<Publication, String>? {
        _state.value = State.Fetching(entry.title)
        _library.value = _library.value.queueing(
            Download(
                id = entry.id,
                title = entry.title,
                remote = link.href,
                mediaType = link.mediaType,
                state = Download.State.Running,
            ),
        ).marking(entry.id, Download.State.Running)

        return try {
            val bytes = client.bytes(link.href, credential)
            val file = withContext(Dispatchers.IO) { write(bytes, entry, link) }
            // Indexing *is* the verification. `offline-downloads` requires integrity to be
            // checked "before it is marked available offline", and with no checksum from the
            // server the honest check is whether the bytes are a publication this app can
            // open. A truncated archive fails here rather than at the first page turn.
            val publication = PublicationIndexer.index(file, entry.series)
            _library.value = _library.value
                .advancing(entry.id, bytes.size.toLong(), bytes.size.toLong())
                .marking(entry.id, Download.State.Finished)
            store?.save(_library.value)
            _state.value = State.Idle
            publication to file.absolutePath
        } catch (error: OpdsError) {
            fail(entry.id, CatalogueMessages.describe(context, error))
            null
        } catch (error: IOException) {
            fail(entry.id, CatalogueMessages.reachability(context, error))
            null
        }
    }

    /**
     * Records a failure, throws away the partial file, and tells the reader.
     *
     * The file goes because it did not verify, and a half-written archive left on disk is
     * counted by the storage view as a book the reader has.
     */
    private fun fail(id: String, reason: String) {
        _library.value = _library.value.failing(id, reason)
        _library.value[id]?.let { download ->
            store?.let { it.delete(it.location(id, extensionOf(download.mediaType))) }
        }
        store?.save(_library.value)
        _state.value = State.Failed(reason)
    }

    /** Puts the banner away, after a failure the reader has read. */
    fun clear() {
        _state.value = State.Idle
    }

    /**
     * Where a fetched publication is put.
     *
     * The store decides, because the store is what knows which directory the backup rules
     * exclude and how a file is named from an identity.
     */
    private fun write(bytes: ByteArray, entry: OpdsEntry, link: OpdsAcquisition): File {
        val store = store ?: throw IOException("no download store")
        store.prepare()
        val file = store.location(entry.id, extensionOf(link.mediaType))
        file.writeBytes(bytes)
        return file
    }

    companion object {
        /**
         * Which acquisition to take when the entry offers several.
         *
         * `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user
         * choose another format". EPUB first, then the comic containers, then PDF -- a comic
         * offered as both CBZ and PDF is a comic, and the PDF is a worse copy of it.
         */
        fun best(entry: OpdsEntry): OpdsAcquisition? = readable(entry).minByOrNull(::rank)

        /** Every acquisition this app could act on, in the order the feed listed them. */
        fun readable(entry: OpdsEntry): List<OpdsAcquisition> = entry.acquisitions.filter {
            it.kind.isFetchable && PublicationFormat.ofMediaType(it.mediaType)?.isOpenable == true
        }

        private fun rank(acquisition: OpdsAcquisition): Int =
            when (PublicationFormat.ofMediaType(acquisition.mediaType)) {
                PublicationFormat.EPUB -> 0
                PublicationFormat.CBZ, PublicationFormat.CBT, PublicationFormat.CBR -> 1
                PublicationFormat.PDF -> 2
                else -> 3
            }
    }
}
