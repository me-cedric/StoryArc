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
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.format.CoverCache
import app.storyarc.core.format.IndexException
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.MeteredDownload
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.StorageHeadroom
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
    /**
     * The origin of the catalogue this queue is downloading from.
     *
     * An acquisition href is a URL the *server* chose, and this queue is the one place in
     * the app that carries a credential to one with nobody watching. Null only where there
     * is no catalogue behind the queue.
     */
    origin: OpdsOrigin? = null,
    /**
     * What the reader has asked of the queue.
     *
     * A function rather than a value: `offline-downloads` requires a paused queue to
     * "resume automatically when [Wi-Fi] returns", so the answer has to be re-asked rather
     * than captured once at construction.
     */
    private val settings: () -> AppSettings = { AppSettings.Defaults },
) {
    private val _library = MutableStateFlow(
        // Nothing outside this process carries a transfer on Android, so a download the
        // store calls running is one whose process died mid-flight. It goes back in the
        // queue rather than waiting for a coroutine that no longer exists.
        (store?.library() ?: DownloadLibrary()).reclaiming(emptySet()),
    )

    /** What has been downloaded and what is on its way. */
    val library: StateFlow<DownloadLibrary> = _library.asStateFlow()

    private val client = OpdsClient(pins, origin)
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

    /**
     * The publications the reader has agreed to spend mobile data on.
     *
     * In memory only, and deliberately: `offline-downloads` grants the override for one
     * item, at one moment, on one connection. A grant that outlived the process would be a
     * standing permission the reader never gave.
     */
    private val overridden = mutableSetOf<String>()

    /**
     * Whether the reader has to be asked before this one is queued.
     *
     * `offline-downloads`' *Overriding once*. The answer is [MeteredDownload]'s; what this
     * adds is the two facts it needs -- whether the link is one to be careful with, and
     * whether this publication already carries a grant.
     */
    fun needsMeteredConfirmation(entry: OpdsEntry): Boolean = MeteredDownload.needsConfirmation(
        isMetered = NetworkCost.isCareful(context),
        isOverridden = entry.id in overridden,
    )

    /**
     * What the confirmation can state about the size, or null when nothing can.
     *
     * `offline-downloads` asks the confirmation to state the size, and states elsewhere that
     * a size is shown only when the server gave one -- "a fabricated one is worse than an
     * honest blank". An OPDS acquisition link carries no length, so the honest answer before
     * a first download is usually nothing, and the dialog says so in words rather than
     * showing a number nobody supplied.
     */
    fun statedBytes(entry: OpdsEntry): Long? = _library.value[entry.id]?.expectedBytes

    /** Whether this one may start over the connection the device is on. */
    private fun mayStart(download: Download): Boolean = MeteredDownload.mayStart(
        wifiOnly = settings().downloadOverWifiOnly,
        isMetered = !isOnWifi(),
        isOverridden = download.id in overridden,
    )

    /** Whether anything still to do carries a grant. */
    private fun hasOverriddenPending(): Boolean =
        _library.value.pending.any { it.id in overridden }

    /**
     * Adds a download and starts it when there is room.
     *
     * @param overridingMeteredConnection the reader was asked whether to spend mobile data
     *   on this one, and said yes. `offline-downloads` grants that "for that item only",
     *   which is why it is recorded against the id rather than flipping a setting -- see
     *   [MeteredDownload].
     */
    fun enqueue(
        entry: OpdsEntry,
        acquisition: OpdsAcquisition,
        overridingMeteredConnection: Boolean = false,
    ) {
        if (overridingMeteredConnection) overridden += entry.id
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

    /**
     * Enqueues, then waits for the file -- for a reader who tapped to read it now.
     *
     * A reader who pressed *Read* on a metered link has explicitly asked for this one
     * publication, which is exactly the override `offline-downloads` describes -- so the
     * confirmation is the caller's to have already presented, and the grant travels with the
     * call rather than being asked for twice.
     */
    suspend fun fetch(
        entry: OpdsEntry,
        acquisition: OpdsAcquisition,
        overridingMeteredConnection: Boolean = false,
    ): File? {
        downloaded(entry)?.let { return it }
        val waiter = CompletableDeferred<File?>()
        waiting.getOrPut(entry.id) { mutableListOf() }.add(waiter)
        enqueue(entry, acquisition, overridingMeteredConnection)
        return waiter.await()
    }

    /** Stops a download and forgets it, deleting whatever arrived. */
    fun cancel(id: String) {
        running.remove(id)?.cancel()
        follow()
        remove(id)
        finish(id, null)
        pump()
    }

    /** Holds a download where it is. The reader asked, so the reason says so. */
    fun pause(id: String) {
        running.remove(id)?.cancel()
        follow()
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
        val file = store?.location(download) ?: return null
        return file.takeIf { it.exists() }
    }

    /** Forgets a download and deletes its file. */
    fun remove(id: String) {
        _library.value[id]?.let { download ->
            // The whole directory, not the one file: a stem this build did not choose is
            // still this download's bytes, and leaving them is what made the storage total lie.
            store?.remove(download)
        }
        _library.value = _library.value.removing(id)
        store?.save(_library.value)
    }

    private fun extensionOf(mediaType: String): String =
        PublicationFormat.ofMediaType(mediaType)?.name?.lowercase() ?: "bin"

    /**
     * Why the queue is not starting anything, if it is not.
     *
     * Null when it may run. `offline-downloads` requires a held queue to *say* what it is
     * waiting for -- "waiting for Wi-Fi" and "the storage limit is reached" are different
     * situations with different remedies, and a stalled list that explains neither is the
     * worst of the three.
     */
    fun held(): Held? {
        if (spaceIsLow) return Held.OutOfSpace
        val current = settings()
        // Not held when something in the queue carries a metered override: one granted
        // publication is running, and a queue that reported itself stopped while bytes were
        // arriving would be the lie this function exists to prevent.
        if (current.downloadOverWifiOnly && !isOnWifi() && !hasOverriddenPending()) {
            return Held.WaitingForWifi
        }
        val limit = current.maximumDownloadBytes ?: return null
        return if (_library.value.bytesOnDisk >= limit) Held.StorageFull else null
    }

    /** What is stopping the queue. */
    enum class Held {
        WaitingForWifi,
        StorageFull,

        /** The device itself is short of room, whatever the reader's own limit says. */
        OutOfSpace,
    }

    /**
     * Whether the volume was short of room the last time it was asked.
     *
     * Cached rather than asked on demand: [held] is read from a composable, and a filesystem
     * stat per recomposition is a cost a screen should not pay. Refreshed wherever the queue
     * is about to act -- which is the only moment the answer changes anything.
     */
    private var spaceIsLow = false

    /**
     * Whether the cover cache has already been given up for this shortage.
     *
     * `offline-downloads` evicts it "before any downloaded publication", and once is enough:
     * re-clearing an empty cache on every pump would be work that frees nothing and hides the
     * fact that the eviction did not help.
     */
    private var coversEvicted = false

    /** Asks the volume how much room is left, and remembers the answer. */
    private fun refreshHeadroom() {
        spaceIsLow = StorageHeadroom.isLow(store?.availableBytes())
    }

    /**
     * Stops the queue because the device is full, and says so on every row.
     *
     * `offline-downloads`' *Device storage is low*, all three clauses:
     *
     * - **"pauses downloads"** -- every queued and running transfer becomes
     *   [Download.Pause.OUT_OF_SPACE], which is the state and the sentence that have been in
     *   the app, translated, and unreachable since the queue was written.
     * - **"evicts the cover cache before any downloaded publication"** -- the cache goes,
     *   once. It is the only thing here the app may throw away without asking, because every
     *   byte of it can be drawn again from a file the reader still has.
     * - **"never deletes a download without asking"** -- nothing below deletes anything. The
     *   bytes already fetched stay where they are and the transfer resumes from them when
     *   there is room, which is the whole point of pausing rather than cancelling.
     */
    private fun holdForSpace() {
        running.values.forEach { it.cancel() }
        running.clear()
        follow()
        _library.value = _library.value.pausingForSpace()
        store?.save(_library.value)
        if (coversEvicted) return
        coversEvicted = true
        CoverCache(File(context.cacheDir, "covers")).clear()
    }

    /** Puts back what was only waiting for room, once there is some. */
    private fun releaseSpaceHolds() {
        coversEvicted = false
        val waiting = _library.value.resumingAfterSpace()
        if (waiting == _library.value) return
        _library.value = waiting
        store?.save(waiting)
    }

    private fun isOnWifi(): Boolean {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    /**
     * Re-examines a held queue.
     *
     * Called when the network or the settings change. `offline-downloads` promises downloads
     * "resume automatically when [Wi-Fi] returns", and automatically means without the
     * reader going back to the screen.
     */
    fun reconsider() = pump()

    /** Starts whatever should be running and is not. */
    private fun pump() {
        refreshHeadroom()
        if (spaceIsLow) {
            holdForSpace()
            return
        }
        releaseSpaceHolds()
        // Held rather than cancelled: the queue keeps its order and its progress, and
        // starts again by itself the next time this is asked.
        //
        // The reader's own storage maximum stops everything, because an override is about
        // the *connection* and says nothing about the disk. Waiting for Wi-Fi is decided per
        // download instead -- `offline-downloads` grants the override "for that item only",
        // so one granted publication may run while the rest of the queue waits.
        if (held() == Held.StorageFull) return
        val ready = _library.value.downloads
            .filter { it.state == Download.State.Queued && mayStart(it) }
        ready.take(maxOf(0, concurrency - running.size)).forEach { download ->
            // No catalogue entry is needed to fetch one: the record carries the address, the
            // media type and the name. An entry enqueued by a previous launch is gone from
            // `entries`, and a download that only resumes while the app that started it is
            // still alive is not the offline promise `offline-downloads` makes.
            val seriesHint = entries[download.id]?.series
            _library.value = _library.value.marking(download.id, Download.State.Running)
            running[download.id] = scope.launch { transfer(download, seriesHint) }
        }
        follow()
    }

    /**
     * Tells the platform how much work there is, so the process survives long enough to do it.
     *
     * Called wherever [running] changes. `offline-downloads` asks for a backgrounded download
     * to continue as far as the platform allows, and on Android that is exactly as far as the
     * process lives.
     */
    private fun follow() = DownloadService.follow(context, running.size)

    private suspend fun transfer(download: Download, seriesHint: String?) {
        while (true) {
            val file = attempt(download, seriesHint)
            if (file != null) {
                running.remove(download.id)
                follow()
                finish(download.id, file)
                pump()
                return
            }
            val current = _library.value[download.id] ?: break
            // `offline-downloads`: "a failed verification re-queues it once". The bytes
            // arrived and were not a book, so [attempt] put the download back in the queue
            // rather than failing it. Left there for the pump to start again, and -- the
            // part that matters -- nobody waiting to *read* it is told it failed, because
            // it has not.
            if (current.state == Download.State.Queued) {
                running.remove(download.id)
                follow()
                pump()
                return
            }
            val failed = current.state as? Download.State.Failed ?: break
            if (!DownloadLibrary.shouldRetry(current)) break
            delay(DownloadLibrary.backoffMillis(failed.attempts))
            _library.value = _library.value.marking(download.id, Download.State.Running)
        }
        running.remove(download.id)
        follow()
        finish(download.id, null)
        pump()
    }

    /** One attempt, with no opinion about whether there will be another. */
    private suspend fun attempt(download: Download, seriesHint: String?): File? = try {
        val bytes = client.bytes(download.remote, credential(download.id))
        val store = store ?: throw IOException("no download store")
        val file = withContext(Dispatchers.IO) {
            val target = store.location(download)
            store.prepare(target)
            target.apply { writeBytes(bytes) }
        }
        // Indexing *is* the verification. `offline-downloads` requires integrity to be
        // checked "before it is marked available offline", and with no checksum from the
        // server the honest check is whether the bytes are a publication this app can open.
        PublicationIndexer.index(file, catalogueSeries = seriesHint)
        _library.value = _library.value
            .advancing(download.id, bytes.size.toLong(), bytes.size.toLong())
            .marking(download.id, Download.State.Finished)
        store.save(_library.value)
        file
    } catch (error: IndexException) {
        // Indexing *is* the verification, so this is where `offline-downloads`' "a failed
        // verification re-queues it once" is answered -- and the two ways it can fail get
        // different answers.
        //
        // **An unsupported format is not a failed verification.** The bytes are exactly
        // what the server holds; the app simply has no decoder for them. Fetching them
        // again produces the same format, so this is terminal and always was.
        //
        // **Unreadable bytes are a failed verification.** A truncated archive, a central
        // directory that is not there, a file that stops mid-entry -- the likeliest cause is
        // the transfer rather than the publication, and one more fetch is the cheapest way
        // to find out. Exactly one: a second identical result is the server's answer, and
        // asking a third time is asking a question already answered twice.
        //
        // Its own branch because `IndexException` extends `Exception` rather than
        // `IOException`: without it a truncated archive threw straight out of this
        // coroutine, and the scope it runs in has a `SupervisorJob` and no handler, so a
        // failed verification took the app down instead of marking the download failed.
        when (error) {
            is IndexException.Unsupported -> fail(
                download.id,
                context.getString(R.string.catalogue_acquire_unsupported, error.format),
                retryable = false,
            )
            is IndexException.Unreadable -> failVerification(
                download.id,
                context.getString(R.string.catalogue_acquire_unreadable),
            )
        }
        null
    } catch (error: OpdsError) {
        fail(download.id, CatalogueMessages.describe(context, error), error.isTransient)
        null
    } catch (error: IOException) {
        fail(download.id, CatalogueMessages.reachability(context, error))
        null
    }

    /**
     * Records that the bytes arrived and were not a publication.
     *
     * The corrupt file goes either way. On the re-queue it has to, because the next attempt
     * writes to the same path and half a comic left there is what the storage total would
     * count; on the second failure it has to for the same reason [fail] has always removed
     * it. [DownloadLibrary.failingVerification] decides which of the two this is, and that
     * rule is asserted rather than living here.
     */
    private fun failVerification(id: String, reason: String) {
        _library.value = _library.value.failingVerification(id, reason)
        _library.value[id]?.let { download -> store?.remove(download) }
        store?.save(_library.value)
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
            store?.remove(download)
        }
        store?.save(_library.value)
    }

    /** Hands the result to whoever was waiting to read it. */
    private fun finish(id: String, file: File?) {
        waiting.remove(id)?.forEach { it.complete(file) }
    }

}
