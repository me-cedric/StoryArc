package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.persistence.AnnotationStore
import app.storyarc.core.smb.SmbReachability
import app.storyarc.feature.library.KavitaPage
import app.storyarc.feature.library.KavitaSync
import app.storyarc.feature.reader.ReaderScreen
import app.storyarc.feature.reader.ReaderViewModel
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
    val blockedSince by SmbReachability.blockedSince.collectAsStateWithLifecycle()

    // Keyed on the publication so opening a different one builds a fresh model rather than
    // showing the previous book's pages.
    val viewModel = remember(publication.id) {
        ReaderViewModel(
            publication,
            activity.contentResolver,
            screen.path,
            dependencies.progress,
            // The same store the ebook reader uses, and a different scope inside it:
            // `reading-themes` gives comics and reflowable text separate defaults.
            shelfStore = dependencies.readerPreferences,
            // And the same store the ebook reader marks into. A PDF that carries text is
            // highlighted the same way a novel is, and `ebook-reader` lists both in one
            // place.
            annotationStore = AnnotationStore.open(activity),
        )
    }

    // Closing the reader is one moment `kavita-server` sends a position. Leaving for the
    // home screen is the other, and the commoner one: a phone is usually closed by going
    // home, and a position that only travelled on a clean exit would be the evening's
    // reading lost.
    val report: suspend () -> Unit = {
        val origin = dependencies.kavitaProgress.origin(publication.id)
        val page = dependencies.progress.progress(publication.identity)?.position
        if (origin != null && page is ReadingPosition.Page) {
            KavitaSync.report(
                dependencies.kavitaProgress,
                host.library.registry.value.sources
                    .firstOrNull { it.id.toString() == origin.sourceId }
                    ?.let { KavitaPage.of(it, dependencies.credentials)?.address },
                origin,
                page.index,
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

    ReaderScreen(
        viewModel = viewModel,
        onClose = {
            onClose()
            activity.lifecycleScope.launch { report() }
        },
        blockedSince = blockedSince,
        onDismissTrouble = { SmbReachability.clear() },
        // Only for a publication that lives on a share. Everything else is already on the
        // device, and offering to download it would be offering nothing.
        onDownloadForOffline = screen.path
            .takeIf { it.startsWith("smb://") }
            ?.let { remote ->
                {
                    activity.lifecycleScope.launch {
                        keepForOffline(dependencies.downloads, publication, remote)
                            ?.let { local -> host.open(publication, local) }
                        SmbReachability.clear()
                    }
                }
            },
        // `comic-reader`: the end of one volume offers the next. The app layer answers this
        // because it is the only place that can see both the reader and the library, and
        // the library is what knows a reading list may have a different opinion about what
        // comes next than the series does.
        previousInSeries = host.library.previous(publication),
        nextInSeries = host.library.next(publication),
        onOpen = { next -> host.library.location(next)?.let { host.open(next, it) } },
    )
}
