package app.storyarc

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.QuickActionRequest
import app.storyarc.core.persistence.finishedDownload
import app.storyarc.core.persistence.removeAfterFinishing
import app.storyarc.navigation.AppDestination
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** `offline-downloads`: "the removal is undoable for 10 seconds". */
private const val UNDO_WINDOW_MILLIS = 10_000L

/**
 * How long to keep looking for a publication a quick action named.
 *
 * `sources` restores the cached catalogue before it walks anything, so the usual answer
 * arrives in a frame or two. The cap is what stops a cold start with a slow share from
 * throwing the reader into a book five minutes after they asked for it, by which time they
 * are somewhere else. iOS's `ReadingContinuity` waits the same five seconds.
 */
private const val RESOLVE_ATTEMPTS = 20
private const val RESOLVE_INTERVAL_MILLIS = 250L

/**
 * Everything that arrives from outside the app, answered in one place.
 *
 * A file the system handed over, an entry chosen from the launcher's own menu, the menu
 * StoryArc publishes back to it, and the download a finished book leaves behind. None of
 * these is a screen, all of them change where the app is, and each used to sit inside
 * whichever branch of the old `if` chain happened to be composed when it fired — which is
 * why the finished-download sweep had to be written into the library branch and explain
 * itself for six lines.
 */
@Composable
internal fun AppIntents(
    host: AppHost,
    settings: AppSettings,
    handedOver: MutableState<Uri?>,
    quickAction: MutableState<QuickActionRequest?>,
    /** A reader is on screen, so this is not the moment to take a download away. */
    isReading: Boolean,
    onRefusedFile: (OpenedFile.Outcome) -> Unit,
) {
    val activity = host.activity

    // A file the system handed over. Keyed on the `Uri` so a second file opens, and cleared
    // as soon as it is consumed so a rotation does not reopen the last one.
    val incoming = handedOver.value
    LaunchedEffect(incoming) {
        val uri = incoming ?: return@LaunchedEffect
        handedOver.value = null
        when (val outcome = OpenedFile.index(activity.contentResolver, uri)) {
            // The same door the library goes through, so a file that arrives from a file
            // manager is routed to a reader by what it *is*, exactly as one chosen from a
            // shelf would be.
            is OpenedFile.Outcome.Opened -> host.open(outcome.publication, outcome.decoderPath)
            else -> onRefusedFile(outcome)
        }
    }

    // `native-experience`: the launcher's own menu, published from the shelf it describes.
    // Republished whenever the list itself changes — a reading position moving, a download
    // arriving — so the entry a reader sees on their home screen names the book they were
    // last on.
    val continueReading by host.library.continueReading.collectAsStateWithLifecycle()
    val hasDownloads = host.downloads.value.downloads.isNotEmpty()
    LaunchedEffect(continueReading.firstOrNull(), hasDownloads) {
        // The activity's context, never the application's: `localization` lets the reader
        // override the interface language, and that override lives on this activity.
        // Published from the application context, every entry would be in the system's
        // language while the app was in the reader's.
        HomeScreenActions.publish(activity, continueReading.firstOrNull(), hasDownloads)
    }

    // What the reader chose from that menu. Cleared as soon as it is taken, so a rotation
    // does not act on it a second time.
    var wanted by remember { mutableStateOf<String?>(null) }
    val chosenAction = quickAction.value
    LaunchedEffect(chosenAction) {
        when (chosenAction) {
            null -> Unit
            is QuickActionRequest.ContinueReading -> {
                quickAction.value = null
                wanted = chosenAction.publicationId
            }
            // The entry promises the shelf, not wherever the reader last was, so the
            // destination opens at its root — one call, where unwinding eight pieces of
            // state by hand used to be nine lines that had to name all of them.
            QuickActionRequest.Library -> {
                quickAction.value = null
                host.navigate { open(AppDestination.LIBRARY) }
            }
            QuickActionRequest.Downloads -> {
                quickAction.value = null
                host.downloads.value = host.dependencies.downloads.library()
                host.navigate { open(AppDestination.DOWNLOADS) }
            }
        }
    }

    // Waiting rather than looking, because a quick action lands on a cold start: the shelf
    // is still empty at the moment the request arrives. Giving up is part of the behaviour
    // rather than a failure of it — the reader lands where they would have landed anyway.
    LaunchedEffect(wanted) {
        val id = wanted ?: return@LaunchedEffect
        repeat(RESOLVE_ATTEMPTS) {
            val publication = host.library.publications.value.firstOrNull { it.id == id }
            if (publication != null) {
                wanted = null
                host.library.location(publication)?.let { host.open(publication, it) }
                return@LaunchedEffect
            }
            delay(RESOLVE_INTERVAL_MILLIS)
        }
        wanted = null
    }

    ForgetFinishedDownloads(host = host, settings = settings, isReading = isReading)
}

/**
 * `offline-downloads`: a finished publication's download goes, and the reader has ten
 * seconds to say otherwise.
 *
 * Swept between books rather than in a reader's close path, because there are two readers
 * and the EPUB one is a separate activity — coming back out of a reader is the one moment
 * both of them pass through.
 */
@Composable
private fun ForgetFinishedDownloads(host: AppHost, settings: AppSettings, isReading: Boolean) {
    val publications by host.library.publications.collectAsStateWithLifecycle()
    LaunchedEffect(settings.removeDownloadsAfterFinishing, publications, isReading) {
        if (isReading || !settings.removeDownloadsAfterFinishing) return@LaunchedEffect
        val store = host.dependencies.downloads
        val target = finishedDownload(store, host.downloads.value) { path ->
            host.dependencies.progress
                .progress(PublicationIdentity(normalizedPath = path))
                ?.isFinished == true
        } ?: return@LaunchedEffect
        removeAfterFinishing(store, host.downloads.value, target.id)?.let { (without, taken) ->
            host.downloads.value = without
            host.removed.value?.settle()
            host.removed.value = taken
            launch {
                delay(UNDO_WINDOW_MILLIS)
                if (host.removed.value === taken) {
                    taken.settle()
                    host.removed.value = null
                }
            }
        }
    }
}
