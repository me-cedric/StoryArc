package app.storyarc.feature.library

import android.content.Context
import android.os.Looper.getMainLooper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadHold
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * A transfer already running has to stop when the connection stops permitting it.
 *
 * `offline-downloads`' *Wi-Fi only* says downloads "pause and state that they are waiting for
 * Wi-Fi, and resume automatically when it returns". [DownloadQueueWakingTest] proved the second
 * half. This suite is the first: `pump` only ever *started* transfers, so a reader who set
 * "download over Wi-Fi only", began a download on Wi-Fi and walked out of range kept
 * downloading over mobile data. The setting they chose to protect their data stopped protecting
 * it the moment a transfer was running -- which is the moment it costs them money.
 *
 * The connection is injected, because `ConnectivityManager` reports Wi-Fi to an emulator
 * whatever the host is on.
 *
 * Nothing here waits on a transfer, which goes to an address that resolves to nothing. The
 * record reaches its state in `pump`, before the transfer coroutine reaches its first
 * suspension. iOS asserts the same six claims in `DownloadQueueConnectionTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueConnectionTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(vararg downloads: Download): DownloadStore =
        DownloadStore.open(context).apply { save(DownloadLibrary(downloads.toList())) }

    private fun queued(id: String, fetched: Long = 0) = Download(
        id = id,
        title = "Harbour Lights 07",
        remote = "https://example.invalid/hl07.epub",
        mediaType = "application/epub+zip",
        state = Download.State.Queued,
        expectedBytes = 8_400_000,
        downloadedBytes = fetched,
    )

    private val waiting = Download.State.Paused(Download.Pause.WAITING_FOR_WIFI)

    private fun queue(store: DownloadStore, wifi: MutableStateFlow<Boolean>) = DownloadQueue(
        context,
        CertificatePins(),
        store,
        settings = { AppSettings(downloadOverWifiOnly = true) },
        onWifi = wifi,
    ).also { shadowOf(getMainLooper()).idle() }

    @Test
    fun `a running transfer is paused when the connection becomes mobile data`() {
        val id = "running-stops"
        val wifi = MutableStateFlow(true)
        val queue = queue(store(queued(id)), wifi)
        assertEquals(Download.State.Running, queue.library.value[id]?.state)

        wifi.value = false

        assertEquals(
            "The transfer kept running over mobile data with Wi-Fi-only on.",
            waiting,
            queue.library.value[id]?.state,
        )
        assertEquals(DownloadHold.WAITING_FOR_WIFI, queue.held())
    }

    @Test
    fun `pausing for the connection keeps the record and the bytes counted against it`() {
        // `offline-downloads` pauses rather than cancels, and "the bytes stay and the transfer
        // resumes from them". Two things carry that: the record, which holds the count, and
        // the partial file, which holds the bytes the next attempt asks the server to carry
        // on from. Losing either is losing the claim.
        val id = "bytes-survive"
        val wifi = MutableStateFlow(true)
        val held = store(queued(id, fetched = 4_000_000))
        val partial = held.partial(queued(id)).apply {
            parentFile?.mkdirs()
            writeBytes(ByteArray(4_000))
        }
        val queue = queue(held, wifi)

        wifi.value = false

        val paused = queue.library.value[id]
        assertEquals(waiting, paused?.state)
        assertEquals(4_000_000L, paused?.downloadedBytes)
        assertEquals(8_400_000L, paused?.expectedBytes)
        assertTrue(
            "A pause deleted the fetched bytes, so the transfer has nothing to resume from.",
            partial.isFile,
        )
        assertEquals(4_000L, partial.length())
    }

    @Test
    fun `a paused download starts again when wifi returns with no screen opened`() {
        val id = "wifi-returns"
        val wifi = MutableStateFlow(true)
        val queue = queue(store(queued(id)), wifi)
        wifi.value = false
        assertEquals(waiting, queue.library.value[id]?.state)

        wifi.value = true

        assertEquals(Download.State.Running, queue.library.value[id]?.state)
        assertNull(queue.held())
    }

    @Test
    fun `a download the reader allowed on mobile data is not paused and the grant is its own`() {
        // `offline-downloads` grants the override "for that item only". A hold that took the
        // granted download with it would refuse the reader the thing they just agreed to pay
        // for; a hold that released the queue behind it would spend the allowance they did not
        // agree to.
        val granted = "granted"
        val other = "other"
        val wifi = MutableStateFlow(true)
        val queue = queue(store(queued(other)), wifi)
        queue.enqueue(
            OpdsEntry(id = granted, title = "Harbour Lights 08"),
            OpdsAcquisition(
                href = "https://example.invalid/hl08.epub",
                mediaType = "application/epub+zip",
                kind = OpdsAcquisition.Kind.OPEN,
            ),
            overridingMeteredConnection = true,
        )

        wifi.value = false

        assertNotEquals(waiting, queue.library.value[granted]?.state)
        assertEquals(
            "The grant released a download the reader never agreed to pay for.",
            waiting,
            queue.library.value[other]?.state,
        )
    }

    @Test
    fun `a queue rebuilt on mobile data is held again and says so`() {
        // The reason is persisted now, so a rebuilt queue reads it back -- and then asks the
        // connection anyway on its first pump, which is what keeps the reason true rather than
        // merely remembered: a process restarted on Wi-Fi puts the row back in the queue and
        // shows no hold at all.
        //
        // The row is held before the store is read again, which is iOS's `theHoldComesBack`
        // step for step. Reading a *running* row here instead left the first queue's transfer
        // in flight against an address that resolves to nothing, so what the second queue read
        // back was whichever of the two won.
        val id = "relaunch"
        val store = store(queued(id))
        val wifi = MutableStateFlow(true)
        val first = queue(store, wifi)
        wifi.value = false
        assertEquals(waiting, first.library.value[id]?.state)

        val second = queue(store, MutableStateFlow(false))

        assertEquals(waiting, second.library.value[id]?.state)
        assertEquals(DownloadHold.WAITING_FOR_WIFI, second.held())
    }

    @Test
    fun `a failed attempt keeps the bytes the next one will carry on from`() {
        // `offline-downloads` names network loss first among the interruptions a download
        // resumes from, and network loss reaches the queue as a failed attempt rather than as
        // a hold. The queue deleted the download's whole directory on every failure, so the
        // partial file went with it and the attempt after the backoff began at zero: the
        // interruption the scenario names first was the one it did not answer.
        val id = "failure-keeps"
        val store = store(queued(id))
        val partial = store.partial(queued(id)).apply {
            parentFile?.mkdirs()
            writeBytes(ByteArray(4_000))
        }
        val queue = queue(store, MutableStateFlow(true))

        val state = failure(queue, id)

        assertTrue("The transfer did not fail, so nothing here was measured: $state", state is Download.State.Failed)
        assertTrue(
            "A failed attempt deleted the fetched bytes, so the retry after it starts at zero.",
            partial.isFile,
        )
        assertEquals(4_000L, partial.length())
    }

    /**
     * The record once its transfer has failed, or whatever it reached before the wait ran out.
     *
     * The address resolves to nothing, so the failure is a name lookup and arrives in
     * milliseconds. Driven rather than awaited because the transfer's own work is on
     * `Dispatchers.IO` and only its ending is on the looper this test can idle.
     */
    private fun failure(queue: DownloadQueue, id: String): Download.State? {
        val deadline = System.currentTimeMillis() + FAILURE_WAIT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            shadowOf(getMainLooper()).idle()
            val state = queue.library.value[id]?.state
            if (state is Download.State.Failed) return state
            Thread.sleep(POLL_MILLIS)
        }
        return queue.library.value[id]?.state
    }

    @Test
    fun `a connection that drops and returns ten times moves the row ten times not more`() {
        // What ten transitions in ten seconds do, stated. Each *change* moves the record
        // exactly once, and nothing else: the flow reports only a connection that differs, and
        // a pass that alters no record returns the same library, so the store is not written
        // at all -- asserted on the rule itself in `DownloadWifiHoldTest`.
        //
        // So the reader pays ten writes for ten real transitions, and five fresh starts. Each
        // of those five carries on from the partial file the hold before it left, rather than
        // beginning at zero, which is the part of this that costs them data rather than disk.
        val id = "flapping"
        val wifi = MutableStateFlow(true)
        val queue = queue(store(queued(id)), wifi)
        val seen = mutableListOf<Download.State?>()

        repeat(5) {
            wifi.value = true
            seen += queue.library.value[id]?.state
            wifi.value = false
            seen += queue.library.value[id]?.state
        }

        val expected = (0 until 5).flatMap { listOf(Download.State.Running, waiting) }
        assertEquals("Ten transitions did not move the row exactly ten times.", expected, seen)
    }

    private companion object {
        /** Long enough for a name lookup that cannot succeed, short enough to notice a hang. */
        const val FAILURE_WAIT_MILLIS = 20_000L

        const val POLL_MILLIS = 10L
    }
}
