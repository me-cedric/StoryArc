package app.storyarc.feature.library

import android.app.Application
import androidx.lifecycle.viewModelScope
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.RetryTrigger
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceProbe
import app.storyarc.core.model.SourceReachability
import app.storyarc.core.persistence.CredentialStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/*
 * When a source is asked again, and what happens when it is.
 *
 * Its own file rather than a tail on `LibraryViewModel`, which is at the length the line cap
 * records for it -- and because keeping the sources answering is one subject with three
 * occasions: the backoff schedule, a regained network, and the app returning to the
 * foreground. iOS split the identical code out of `LibraryModel` into
 * `LibrarySourceHealth.swift` and `SourceRetryTriggers.swift` for the same reason.
 *
 * The *decisions* are not here. `SourceProbe` holds the backoff and the meaning of a status
 * code, and `SourceReachability` holds whether a trigger earns a probe at all -- both in
 * `core/model`, where a test reaches them without a network.
 */

/**
 * Keeps asking, while any source is still away.
 *
 * `sources` asks for more than one probe: an unreachable source is retried "with
 * exponential backoff starting at 5 seconds and capping at 5 minutes", and one that
 * comes back is reconnected "without user action". A single probe on appearance
 * satisfies neither — a reader whose Wi-Fi returns while they are looking at the
 * library would watch it say "Connecting…" until they left the screen and came back.
 *
 * The schedule is [SourceProbe.delayAfter], which is tested without a network. This is
 * only the loop, and it holds a job rather than launching a second one, so a reader
 * leaving and returning does not end up with two.
 *
 * iOS runs the same loop from its `task` modifier, where cancellation is the view's.
 *
 * @param isReading whether a reader has a publication open. `sources`' automatic recovery
 *   must not "interrupt reading", and this loop ran straight through a chapter — every 5 s,
 *   then every 10, up to every 5 minutes, for as long as anything was away. Asked **each
 *   time round** rather than once at the top, because a reader opens a publication *while*
 *   the loop is waiting. Its answer is the app layer's: this class knows about sources and
 *   not about readers.
 */
fun LibraryViewModel.retryUnreachableSources(
    credentials: CredentialStore?,
    pins: CertificatePins,
    isReading: () -> Boolean = { false },
) {
    retryJob?.cancel()
    retryJob = viewModelScope.launch {
        // The first answer, before the schedule. This used to be a separate call the
        // screen made beside this one, so the loop's first check could run before any
        // source had been asked -- and a loop that finds nothing unreachable stops. iOS
        // awaits its probe and then starts the loop; this is the same order.
        probeAndWait(credentials, pins)
        var failures = 0
        while (isActive) {
            val away = _registry.value.sources.any { it.state is SourceConnectionState.Unreachable }
            if (!away) return@launch
            failures += 1
            delay(SourceProbe.delayAfter(failures))
            // Asked after the wait rather than before it: the reader who matters is the one
            // reading *now*, and a five-minute-old answer is the wrong one. `continue`, not
            // `return`: the source is still away and the loop still owes it a probe once the
            // reader closes the book.
            if (isReading()) continue
            probeAndWait(credentials, pins)
        }
    }
}

/** Stops the retry loop. Called when the library goes away and nobody is looking. */
fun LibraryViewModel.stopRetrying() {
    retryJob?.cancel()
    retryJob = null
}

/**
 * One immediate probe, when the system says something changed.
 *
 * `sources`' *Retry policy* names two occasions beside the backoff — connectivity regained,
 * and the app returning to the foreground. [SourceReachability] decides whether a trigger
 * earns a probe, including the clause that a reader who is reading is left alone; this is
 * only what happens when it does. iOS's `LibraryModel.probe(on:credentials:pins:isReading:)`
 * is the same three lines.
 *
 * Launched rather than suspending, so the caller is an effect and not a coroutine: the
 * trigger arrives from the system, on the main thread, at a moment nobody is awaiting.
 */
fun LibraryViewModel.probe(
    trigger: RetryTrigger,
    credentials: CredentialStore?,
    pins: CertificatePins,
    isReading: Boolean,
) {
    if (!SourceReachability.shouldProbe(trigger, _registry.value.sources, isReading)) return
    viewModelScope.launch { probeAndWait(credentials, pins) }
}

/**
 * Asks every source that can be asked, and what each server holds.
 *
 * Internal rather than private: `private` is file-scoped in Kotlin as it is in Swift, and
 * the loop above and the trigger beside it are the two callers.
 */
internal suspend fun LibraryViewModel.probeAndWait(
    credentials: CredentialStore?,
    pins: CertificatePins,
) {
    val reason = getApplication<Application>().getString(R.string.source_state_unauthorized)
    for (source in _registry.value.sources.filter(SourceHealth::canProbe)) {
        val state = SourceHealth.probe(
            source,
            credentials,
            pins,
            System.currentTimeMillis(),
            reason,
        )
        _registry.update { it.marking(source.id, state) }
    }
    // Asked at the same moment, because it is the same question -- what does this
    // server have -- and the add-to sheet cannot fetch it for itself without
    // opening a connection every time a reader long-presses a cover.
    val answered = mutableListOf<KavitaPage>()
    _serverLists.value = _registry.value.sources.flatMap { source ->
        val page = KavitaPage.of(source, credentials) ?: return@flatMap emptyList()
        val lists = runCatching { KavitaClient(page.address).readingLists() }
            .getOrNull() ?: return@flatMap emptyList()
        answered += page
        lists.map { ServerList(page, it.id, it.title) }
    }
    // `collections-and-reading-lists` offers to copy a local list onto a server, and
    // the offer has to be honest before it is taken: only a server that just answered
    // can take one, so an unreachable one leaves the offer disabled rather than
    // failing after the reader has already confirmed it.
    _listServers.value = answered
}
