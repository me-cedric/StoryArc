package app.storyarc

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.kavita.KavitaExchange
import app.storyarc.core.model.Download
import app.storyarc.core.model.ReadingAddress
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.persistence.AnnotationStore
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.canCurlHere
import app.storyarc.core.playback.SpokenAudio
import app.storyarc.feature.library.KavitaPage
import app.storyarc.feature.library.KavitaSync
import app.storyarc.feature.library.offeredNext
import app.storyarc.feature.library.offeredPrevious
import app.storyarc.feature.reader.DownloadCleanupOffer
import app.storyarc.feature.reader.ReaderScreen
import app.storyarc.feature.reader.ReaderViewModel
import app.storyarc.feature.reader.adoptLocalCopy
import app.storyarc.feature.reader.endWaitIfDownloadStopped
import app.storyarc.navigation.Screen
import kotlinx.coroutines.launch

/**
 * The comic reader, and the two things only the app layer can give it: where a position is
 * reported to, and what comes next in the series.
 *
 * The reader takes the whole window — [Screen.Reader] says so, and the shell draws no
 * navigation control while it is on top.
 */
@Composable
internal fun ReaderHost(host: AppHost, screen: Screen.Reader, onClose: () -> Unit) {
    val activity = host.activity
    val dependencies = host.dependencies
    val publication = screen.publication

    // Keyed on the publication so opening a different one builds a fresh model rather than
    // showing the previous book's pages.
    val viewModel = remember(publication.id) {
        ReaderViewModel(
            publication,
            activity.contentResolver,
            screen.path,
            dependencies.progress,
            // The API floor, narrowed by what this device has shown about its own curl.
            // D11: the model holds no `Context`, and the store needs one.
            canCurl = canCurlHere(activity),
            // The same store the ebook reader uses, and a different scope inside it:
            // `reading-themes` gives comics and reflowable text separate defaults.
            shelfStore = dependencies.readerPreferences,
            // And the same store the ebook reader marks into. A PDF that carries text is
            // highlighted the same way a novel is, and `ebook-reader` lists both in one
            // place.
            annotationStore = AnnotationStore.open(activity),
            // dl-core 1.7: a stream that fails to open waits rather than failing while this
            // exact address's own download is still on its way.
            isDownloadPending = {
                val state = dependencies.downloads.library().downloads
                    .firstOrNull { it.remote == screen.path }?.state
                ReadingAddress.isStreamed(screen.path) &&
                    state != null && !state.isFinished && state !is Download.State.Failed
            },
        )
    }

    // `offline-downloads`' *Reading while downloading*. A publication opened at an address
    // that is still arriving switches to the file the moment the transfer finishes, and the
    // reader is told nothing: no page moves, and nothing reopens under them.
    //
    // Driven by the store rather than by a queue, because the reader has no catalogue page
    // and therefore no queue to ask -- and because every queue in the app writes there.
    DisposableEffect(viewModel) {
        val store = dependencies.downloads
        // Once, and only once. The store is written on every queue event, not only this
        // one's, so without this the next download anybody starts would reopen the file
        // under a reader who is already reading it.
        var hasAdopted = false
        val watch = store.watch {
            if (hasAdopted) return@watch
            activity.lifecycleScope.launch {
                val arrived = ReadingAddress.arrived(screen.path, store.library())
                if (arrived == null) {
                    // dl-core 1.7: a download that failed or went away ends a reader's wait.
                    viewModel.endWaitIfDownloadStopped()
                    return@launch
                }
                hasAdopted = viewModel.adoptLocalCopy(
                    activity.contentResolver,
                    store.location(arrived).path,
                )
            }
        }
        onDispose { watch.close() }
    }

    // Closing the reader is one moment `kavita-server` sends a position. Leaving for the
    // home screen is the other, and the commoner one: a phone is usually closed by going
    // home, and a position that only travelled on a clean exit would be the evening's
    // reading lost.
    val report: suspend () -> Unit = {
        val origin = dependencies.kavitaProgress.origin(publication.id)
        val position = dependencies.progress.progress(publication.identity)?.position
        val page = origin?.let { position?.let { p -> pageToReport(p, it) } }
        if (origin != null && page != null) {
            KavitaSync.report(
                dependencies.kavitaProgress,
                host.library.registry.value.sources
                    .firstOrNull { it.id.toString() == origin.sourceId }
                    ?.let { KavitaPage.of(it, dependencies.credentials)?.address },
                origin,
                page,
                dependencies.progress,
            )
        }
    }

    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val watcher = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) {
                activity.lifecycleScope.launch { report() }
            }
        }
        owner.lifecycle.addObserver(watcher)
        onDispose { owner.lifecycle.removeObserver(watcher) }
    }

    // D18: opening this comic or PDF silenced a voice (`ReaderViewModel.open`), and this is
    // where the listener is told so once. The player's own composable, over the page.
    val voiceStopped = remember { SnackbarHostState() }
    VoiceStoppedWord(SpokenAudio.shared, voiceStopped)
    Box(Modifier.fillMaxSize()) {
        ReaderScreen(
            viewModel = viewModel,
            onClose = {
                onClose()
                activity.lifecycleScope.launch { report() }
            },
            // D7: `null` when this publication was never a download.
            // Both actions only record the choice; the sweep acts on it when the reader closes.
            downloadCleanup = host.downloads.value[publication.id]?.let {
                val choices = dependencies.cleanupChoices
                val isSweeping = dependencies.settings.settings().removeDownloadsAfterFinishing
                DownloadCleanupOffer(
                    isRemovedOnClose = { choices.isRemovedOnClose(publication.id, isSweeping) },
                    onRemove = { choices.removeOnClose(publication.id) },
                    onKeep = { choices.keep(publication.id) },
                )
            },
            // Only for a publication that lives on a share. Everything else is already on the
            // device, and offering to download it would be offering nothing.
            //
            // Answers whether the copy landed, so `NetworkNotice` can say so when it did not --
            // the share is still unreachable then, which is the entire reason the offer exists.
            onDownloadForOffline = screen.path
                .takeIf { it.startsWith("smb://") }
                ?.let { remote ->
                    suspend {
                        val local = keepForOffline(dependencies.queue, dependencies.downloads, publication, remote)
                        if (local != null) host.open(publication, local)
                        local != null
                    }
                },
            // `comic-reader`: the end of one volume offers the next. The app layer answers this
            // because it is the only place that can see both the reader and the library, and
            // the library is what knows a reading list may have a different opinion about what
            // comes next than the series does.
            // Tasks 7.3 and 7.14: a server reading list the reader is inside wins over the local
            // library's own guess, and nothing is offered that choosing could not open.
            previousInSeries = host.library.offeredPrevious(publication),
            nextInSeries = host.library.offeredNext(publication),
            onOpen = host::openEntry,
        )
        SnackbarHost(voiceStopped, Modifier.align(Alignment.TopCenter).safeDrawingPadding())
    }
}

/**
 * The page number a recorded position reports to Kavita, or null when there is nothing to
 * convert it with.
 *
 * A reflowable position -- an EPUB's -- carries no page number of its own, only a
 * fraction. [KavitaExchange.pageNumber] is the one place that turns a fraction into a
 * page, and it needs the chapter's own length to do it, which is why [KavitaOrigin] now
 * carries it. `origin.pages == 0` means an origin remembered before that field existed, or
 * a chapter the server never reported a length for -- nothing to convert against, so
 * nothing is sent, the same as before this fix.
 */
internal fun pageToReport(position: ReadingPosition, origin: KavitaOrigin): Int? = when (position) {
    is ReadingPosition.Page -> position.index
    is ReadingPosition.Reflowable, is ReadingPosition.Listening ->
        if (origin.pages > 0) KavitaExchange.pageNumber(position, origin.pages) else null
}
