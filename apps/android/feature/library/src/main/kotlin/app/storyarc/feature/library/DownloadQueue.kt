package app.storyarc.feature.library

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.persistence.DownloadStore
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The download queue: what is waiting, what is running, and what the reader can do to it.
 *
 * `offline-downloads`' second requirement, which asks for "per-item and global pause, resume,
 * cancel" and for "a bounded number [to] run concurrently, and the bound ... lowered on a
 * metered connection".
 *
 * Before this, a download was a blocking fetch in the foreground: tapping Download on a
 * four-hundred-megabyte comic meant waiting for it with no way to stop. Now a tap enqueues
 * and returns, and the queue does the waiting. iOS's `DownloadQueue` is the same object.
 */
class DownloadQueue(
    private val context: Context,
    pins: CertificatePins,
    private val store: DownloadStore?,
    private val credential: (String) -> OpdsCredential? = { null },
) {
    private val _library = MutableStateFlow(store?.library() ?: DownloadLibrary())

    /** What has been downloaded and what is on its way. */
    val library: StateFlow<DownloadLibrary> = _library.asStateFlow()

    private val client = OpdsClient(pins)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** The transfer for each running download, so it can be cancelled. */
    private val running = mutableMapOf<String, Job>()

    /** Callers waiting for a particular download to land, because they mean to open it. */
    private val waiting = mutableMapOf<String, MutableList<CompletableDeferred<File?>>>()

    /** What each queued download is *of*, so a retry has an entry to index against. */
    private val entries = mutableMapOf<String, OpdsEntry>()

    /**
     * How many transfers run at once.
     *
     * Two on an ordinary connection: enough that a slow server does not stall the whole
     * queue, few enough that a reader's bandwidth is not divided six ways. One on a metered
     * connection, which is what `offline-downloads` means by lowering the bound -- Data Saver
     * and a metered hotspot both land here.
     */
    private val concurrency: Int get() = if (NetworkCost.isCareful(context)) 1 else 2

    /** Adds a download and starts it when there is room. */
    fun enqueue(entry: OpdsEntry, acquisition: OpdsAcquisition) {
        _library.value = _library.value.queueing(
            Download(
                id = entry.id,
                title = entry.title,
                remote = acquisition.href,
                mediaType = acquisition.mediaType,
            ),
        )
        entries[entry.id] = entry
        store?.save(_library.value)
        pump()
    }

    /** Enqueues, then waits for the file -- for a reader who tapped to read it now. */
    suspend fun fetch(entry: OpdsEntry, acquisition: OpdsAcquisition): File? {
        downloaded(entry)?.let { return it }
        val waiter = CompletableDeferred<File?>()
        waiting.getOrPut(entry.id) { mutableListOf() }.add(waiter)
        enqueue(entry, acquisition)
        return waiter.await()
    }

    /** Stops a download and forgets it, deleting whatever arrived. */
    fun cancel(id: String) {
        running.remove(id)?.cancel()
        remove(id)
        finish(id, null)
        pump()
    }

    /** Holds a download where it is. The reader asked, so the reason says so. */
    fun pause(id: String) {
        running.remove(id)?.cancel()
        _library.value = _library.value.marking(id, Download.State.Paused(Download.Pause.BY_READER))
        store?.save(_library.value)
        finish(id, null)
        pump()
    }

    /** Puts a paused or failed download back in the queue. */
    fun resume(id: String) {
        if (_library.value[id] == null) return
        _library.value = _library.value.marking(id, Download.State.Queued)
        store?.save(_library.value)
        pump()
    }

    /** Moves a download in the queue, which is the order it will be worked through. */
    fun move(id: String, destination: Int) {
        _library.value = _library.value.moving(id, destination)
        store?.save(_library.value)
    }

    /**
     * Where a publication already downloaded lives, if it does.
     *
     * Asked of the filesystem: a download the system reclaimed is one the reader should be
     * offered again rather than shown a missing file.
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

    /** Starts whatever should be running and is not. */
    private fun pump() {
        val ready = _library.value.downloads.filter { it.state == Download.State.Queued }
        ready.take(maxOf(0, concurrency - running.size)).forEach { download ->
            // Enqueued by a previous launch, so nothing here knows what it was. Left queued
            // rather than failed: the reader can tap it again from the catalogue and the
            // record is already correct.
            val entry = entries[download.id] ?: return@forEach
            _library.value = _library.value.marking(download.id, Download.State.Running)
            running[download.id] = scope.launch { transfer(download, entry) }
        }
    }

    private suspend fun transfer(download: Download, entry: OpdsEntry) {
        while (true) {
            val file = attempt(download, entry)
            if (file != null) {
                running.remove(download.id)
                finish(download.id, file)
                pump()
                return
            }
            val current = _library.value[download.id] ?: break
            val failed = current.state as? Download.State.Failed ?: break
            if (!DownloadLibrary.shouldRetry(current)) break
            delay(DownloadLibrary.backoffMillis(failed.attempts))
            _library.value = _library.value.marking(download.id, Download.State.Running)
        }
        running.remove(download.id)
        finish(download.id, null)
        pump()
    }

    /** One attempt, with no opinion about whether there will be another. */
    private suspend fun attempt(download: Download, entry: OpdsEntry): File? = try {
        val bytes = client.bytes(download.remote, credential(download.id))
        val store = store ?: throw IOException("no download store")
        val file = withContext(Dispatchers.IO) {
            store.prepare()
            store.location(download.id, extensionOf(download.mediaType)).apply { writeBytes(bytes) }
        }
        // Indexing *is* the verification. `offline-downloads` requires integrity to be
        // checked "before it is marked available offline", and with no checksum from the
        // server the honest check is whether the bytes are a publication this app can open.
        PublicationIndexer.index(file, entry.series)
        _library.value = _library.value
            .advancing(download.id, bytes.size.toLong(), bytes.size.toLong())
            .marking(download.id, Download.State.Finished)
        store.save(_library.value)
        file
    } catch (error: OpdsError) {
        fail(download.id, CatalogueMessages.describe(context, error), error.isTransient)
        null
    } catch (error: IOException) {
        fail(download.id, CatalogueMessages.reachability(context, error))
        null
    }

    private fun fail(id: String, reason: String, retryable: Boolean = true) {
        _library.value = if (retryable) {
            _library.value.failing(id, reason)
        } else {
            // Marked as though every attempt were spent, so the queue stops asking and the
            // reader sees the reason rather than a spinner that returns twice more.
            _library.value.marking(id, Download.State.Failed(reason, DownloadLibrary.ATTEMPT_LIMIT))
        }
        _library.value[id]?.let { download ->
            store?.let { it.delete(it.location(id, extensionOf(download.mediaType))) }
        }
        store?.save(_library.value)
    }

    /** Hands the result to whoever was waiting to read it. */
    private fun finish(id: String, file: File?) {
        waiting.remove(id)?.forEach { it.complete(file) }
    }

}

/**
 * Which acquisition to take, and which the reader could choose instead.
 *
 * Its own object because the question is about a *catalogue entry*, not about the queue: the
 * grid asks it to decide whether a cell is tappable, long before anything is downloaded.
 */
object CatalogueAcquisition {
    /**
     * `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user choose
     * another format". EPUB first, then the comic containers, then PDF -- a comic offered as
     * both CBZ and PDF is a comic, and the PDF is a worse copy of it.
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
