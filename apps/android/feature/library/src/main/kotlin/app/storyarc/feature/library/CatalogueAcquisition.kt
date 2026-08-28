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
import app.storyarc.core.model.PublicationFormat
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
 * The file lands in the cache directory. `offline-downloads` is a separate capability with
 * its own promises about storage, eviction and a reader's control over both; until that
 * exists, calling this a download would be a claim the app cannot keep. The system may
 * reclaim a cached file, and the catalogue can always be asked again.
 */
class CatalogueAcquisition(
    private val context: Context,
    pins: CertificatePins,
) {
    sealed interface State {
        data object Idle : State
        data class Fetching(val title: String) : State
        data class Failed(val message: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    private val client = OpdsClient(pins)

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
        return try {
            val bytes = client.bytes(link.href, credential)
            val file = withContext(Dispatchers.IO) { write(bytes, entry, link) }
            val publication = PublicationIndexer.index(file, entry.series)
            _state.value = State.Idle
            publication to file.absolutePath
        } catch (error: OpdsError) {
            _state.value = State.Failed(CatalogueMessages.describe(context, error))
            null
        } catch (error: IOException) {
            _state.value = State.Failed(CatalogueMessages.reachability(context, error))
            null
        }
    }

    /** Puts the banner away, after a failure the reader has read. */
    fun clear() {
        _state.value = State.Idle
    }

    /**
     * Where a fetched publication is put.
     *
     * Named by the entry's identifier rather than its title: two catalogues can offer the
     * same title, and a filename collision would hand the reader the wrong book. The
     * extension is kept because the indexer reads it as one signal among several.
     */
    private fun write(bytes: ByteArray, entry: OpdsEntry, link: OpdsAcquisition): File {
        val directory = File(context.cacheDir, "catalogue").apply { mkdirs() }
        val name = entry.id.replace(Regex("[^A-Za-z0-9._-]"), "-")
        val extension = PublicationFormat.ofMediaType(link.mediaType)?.name?.lowercase() ?: "bin"
        val file = File(directory, "$name.$extension")
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
