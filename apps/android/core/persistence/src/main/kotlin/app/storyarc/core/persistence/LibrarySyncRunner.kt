package app.storyarc.core.persistence

import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.model.LibrarySyncOutcome
import app.storyarc.core.model.SyncPlace
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex

/** What the sync is doing, for the Settings line. An unreachable place is grey, never red. */
sealed interface SyncStatus {
    /** No place is chosen. Nothing is written, read or looked for. */
    data object Off : SyncStatus

    /** A place is chosen and no sync ran yet in this launch. */
    data object Idle : SyncStatus

    data object Syncing : SyncStatus

    data class Synced(val atEpochMillis: Long) : SyncStatus

    /** The place did not answer. The library keeps working, and the next trigger tries again. */
    data object Unreachable : SyncStatus

    /** The document in the place cannot be read, by name. Nothing was written over it. */
    data class Refused(val reason: LibraryDocumentFailure) : SyncStatus
}

/**
 * When a sync runs, and what the reader sees of it.
 *
 * `library-sync` tasks 2.4, 4.1, 4.2 and 4.3. Each trigger calls [run]. While no place is chosen,
 * [run] does nothing at all. A trigger that comes while a sync runs makes that sync run once
 * more when it ends, so a position saved during a sync is not left out. Any failure of the place
 * is [SyncStatus.Unreachable] and queues one retry: the next trigger runs even inside the
 * foreground throttle. iOS's `LibrarySyncRunner` is the same runner.
 *
 * @param placeFor the place for a choice, or null when it cannot be built (a removed share).
 * @param sync one read, merge and write with that place: `LibraryTransfer.sync`.
 */
class LibrarySyncRunner(
    private val places: SyncPlaceStore,
    private val placeFor: suspend (SyncPlaceChoice) -> SyncPlace?,
    private val sync: suspend (SyncPlace) -> LibrarySyncOutcome,
    private val now: () -> Long = System::currentTimeMillis,
) {
    enum class Trigger {
        /** The reader chose a place. */
        CHOSEN,

        /** The app came to the foreground. At most one run per [THROTTLE_MILLIS]. */
        FOREGROUND,

        /** The reader left a publication the document carries. */
        LEFT_PUBLICATION,

        /** The platform's periodic background work. */
        BACKGROUND,
    }

    companion object {
        const val THROTTLE_MILLIS = 30_000L
    }

    private val _status = MutableStateFlow(if (places.choice() == null) SyncStatus.Off else SyncStatus.Idle)
    val status: StateFlow<SyncStatus> = _status.asStateFlow()

    private val running = Mutex()
    private val again = AtomicBoolean(false)

    @Volatile private var lastStart: Long? = null

    @Volatile private var retryPending = false

    /** Whether a place is chosen. */
    val isOn: Boolean get() = places.choice() != null

    /**
     * One sync, unless sync is off, the foreground throttle skips it, or a sync is running.
     *
     * @return true when this call ran a sync.
     */
    suspend fun run(trigger: Trigger): Boolean {
        if (places.choice() == null) {
            _status.value = SyncStatus.Off
            return false
        }
        val last = lastStart
        if (trigger == Trigger.FOREGROUND && !retryPending && last != null && now() - last < THROTTLE_MILLIS) {
            return false
        }
        if (!running.tryLock()) {
            again.set(true)
            return false
        }
        try {
            do {
                again.set(false)
                once()
            } while (again.get())
        } finally {
            running.unlock()
        }
        return true
    }

    /**
     * The reader left a publication: its position goes to the place at once.
     *
     * A Kavita publication's position goes to Kavita, not into the document (task 3.7), so it
     * starts no sync.
     */
    suspend fun leftPublication(ownedByKavita: Boolean): Boolean =
        if (ownedByKavita) false else run(Trigger.LEFT_PUBLICATION)

    /** Stores the reader's choice, or turns sync off with null, and says so at once. */
    fun choose(choice: SyncPlaceChoice?) {
        places.choose(choice)
        retryPending = false
        lastStart = null
        _status.value = if (choice == null) SyncStatus.Off else SyncStatus.Idle
    }

    private suspend fun once() {
        val choice = places.choice() ?: run {
            _status.value = SyncStatus.Off
            return
        }
        lastStart = now()
        val before = _status.value
        _status.value = SyncStatus.Syncing
        val outcome = attempt(choice)
        retryPending = outcome == null || outcome == LibrarySyncOutcome.Busy
        _status.value = when (outcome) {
            null -> SyncStatus.Unreachable
            is LibrarySyncOutcome.Synced -> SyncStatus.Synced(now())
            is LibrarySyncOutcome.Refused -> SyncStatus.Refused(outcome.reason)
            // Another device wrote under every attempt. The place answered, so it is not
            // unreachable; the next trigger tries again.
            LibrarySyncOutcome.Busy -> before.takeUnless { it == SyncStatus.Syncing } ?: SyncStatus.Idle
        }
    }

    /** The outcome, or null when the place could not be built or did not answer. */
    private suspend fun attempt(choice: SyncPlaceChoice): LibrarySyncOutcome? {
        var place: SyncPlace? = null
        return try {
            place = placeFor(choice) ?: return null
            sync(place)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (unreachable: Exception) {
            null
        } finally {
            (place as? AutoCloseable)?.let { runCatching { it.close() } }
        }
    }
}
