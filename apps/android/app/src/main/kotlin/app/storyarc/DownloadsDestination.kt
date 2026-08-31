package app.storyarc

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.designsystem.grid.rememberCoverColumns
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.removeAfterFinishing
import app.storyarc.feature.library.isOnDevice
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Everything readable with no network at all, and whatever is still on its way.
 *
 * `offline-downloads` makes this one of the three destinations rather than a page inside
 * Settings, and says why: a reader before a flight wants to see what they can read, not
 * what was fetched. The first cut of this screen was two lists of titles — which is the
 * queue inspector in a new place. This one is a shelf:
 *
 * - **Covers, not rows.** The delta asks for the destination to be presented "with the same
 *   grid, the same cells and the same publication pages as the library", because that is
 *   what makes it a library rather than a list of transfers.
 * - **The queue only while there is one.** "When nothing is in flight the queue is absent
 *   rather than shown empty, and the destination is just the readable library." It is
 *   pinned above the shelf, spanning the grid, because a transfer is not a book yet.
 * - **What the files weigh**, once, at the foot. The question this screen is opened with on
 *   a full phone, and a number with no business competing with artwork.
 * - **Removal, undoably.** A removal from here is undoable "for the same window as any
 *   other download removal", so the bytes are moved aside for ten seconds rather than
 *   deleted — the same mechanism the finish-sweep uses.
 *
 * Nothing here consults a source. The destination is complete in airplane mode and reachable
 * from a cold launch with nothing dimmed and nothing waiting, which is the property the spec
 * names and the one this screen exists to hold.
 */
@Composable
internal fun DownloadsDestination(host: AppHost) {
    val context = LocalContext.current
    val library = host.downloads.value
    val publications by host.library.publications.collectAsStateWithLifecycle()
    val snackbars = remember { SnackbarHostState() }

    var removing by remember { mutableStateOf<Download?>(null) }
    var bytesOnDisk by remember { mutableLongStateOf(0L) }

    // Finished downloads are how a publication fetched from a server comes to be on the
    // shelf at all. The total is asked of the filesystem rather than summed from the record:
    // the system can reclaim a file, and a total counting bytes nobody has is the kind of
    // number that makes a reader distrust the whole screen.
    LaunchedEffect(library) {
        host.library.adoptDownloads()
        // Off the main thread: the total is a walk of the download tree, and a shelf that
        // stutters while it is counted is a shelf that reads as slow.
        bytesOnDisk = withContext(Dispatchers.IO) { host.dependencies.downloads.bytesOnDisk() }
    }

    // The same question the library's availability axis asks — *can I open this with no
    // network* — answered by where the bytes are. A folder the reader picked qualifies as
    // much as a download the app fetched: on a plane, neither needs one.
    val onDevice = publications.filter { isOnDevice(host.library.location(it)) }
    val inFlight = library.downloads.filterNot { it.state.isFinished }

    UndoBar(host, snackbars)

    Scaffold(
        containerColor = LocalStoryArcPalette.current.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
    ) { padding ->
        LazyVerticalGrid(
            // The library shelf's own rule, asked rather than restated here.
            //
            // What entitles this destination to the library's rule is this destination's own
            // spec, not the library's: `offline-downloads`, "Everything on this device" —
            // added by the in-flight `one-library-three-destinations` change, which is what
            // this file exists for — says it is "presented with the same grid, the same cells
            // and the same publication pages as the library". The rule that grid follows is
            // `library-browsing`'s Adaptive-columns scenario.
            //
            // This grid used `GridCells.Adaptive`, which takes a lower bound and no upper one.
            // At the 158 dp tier a 971 dp surface divides into five columns of 175 dp, and the
            // library's stopped at the 168 dp maximum: the readable-range half of that
            // scenario, held on one shelf and not the other.
            //
            // The spacing below matches the library grid's for the same reason — two shelves
            // of one library that answer the same window differently read as two apps — and
            // that means `md` 12, not the `coverGap` 14 the tokens define for exactly this
            // gap. This shelf used `coverGap` and was moved *off* it, because the grid it has
            // to match had already drifted onto `md`. `coverGap` keeps two callers, both
            // horizontal runs rather than grids: Home's shelves and a publication page's
            // series shelf. Which of the two spacings is right is open, and written down in
            // `design.md` §4 rather than left silent — a token dropped without a word is the
            // drift this file was rewritten to stop.
            columns = rememberCoverColumns(),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = StoryArcSpace.gutter,
                end = StoryArcSpace.gutter,
                top = padding.calculateTopPadding() + StoryArcSpace.md,
                bottom = StoryArcSpace.xxl,
            ),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
        ) {
            wide { DestinationTitle(stringResource(R.string.destination_downloads)) }

            if (inFlight.isNotEmpty()) {
                wide { SectionHeading(stringResource(R.string.downloads_destination_in_flight)) }
                items(inFlight, key = { it.id }, span = { GridItemSpan(maxLineSpan) }) { one ->
                    DownloadQueueRow(
                        download = one,
                        // Only a queued download has an order to change: a running one has
                        // started, and the list is short enough that its ends are obvious.
                        canReorder = one.state == Download.State.Queued,
                        onReorder = { later ->
                            host.downloads.value = host.downloads.value.moving(one.id, later)
                            host.dependencies.downloads.save(host.downloads.value)
                        },
                        onStop = { removing = one },
                    )
                }
            }

            if (onDevice.isEmpty() && inFlight.isEmpty()) {
                wide {
                    EmptyDestination(
                        sentence = stringResource(R.string.downloads_destination_empty),
                        onOpenLibrary = { host.goToLibrary() },
                    )
                }
                return@LazyVerticalGrid
            }

            if (onDevice.isNotEmpty()) {
                wide { SectionHeading(stringResource(R.string.downloads_destination_on_device)) }
                items(onDevice, key = { it.id }) { publication ->
                    OnDeviceCover(
                        publication = publication,
                        cover = host.library::cover,
                        // A cover, so the publication's page — the on-device destination is
                        // a shelf like any other and `publication-detail` puts a page behind
                        // every cover on one. Nothing here offers to resume.
                        onOpen = { host.openPage(publication) },
                        // Null for a file the reader picked themselves. A folder they chose
                        // is on this device because they put it there, and an app offering
                        // to delete it from a downloads screen would be reaching outside
                        // what it fetched.
                        onRemove = library[publication.id]?.let { download ->
                            { removing = download }
                        },
                    )
                }
                wide { SpaceUsed(Formatter.formatShortFileSize(context, bytesOnDisk)) }
            }
        }
    }

    removing?.let { download ->
        RemoveDownloadDialog(
            download = download,
            onDismiss = { removing = null },
            onConfirm = {
                removing = null
                host.activity.lifecycleScope.launch { remove(host, download) }
            },
        )
    }
}

/**
 * The ten seconds in which a removal can be taken back.
 *
 * A snackbar, which is Material's answer to exactly this and the one the library already
 * uses for the finish-sweep — so a removal made here and one made for the reader look and
 * behave the same. Letting it time out settles the removal: the bytes waiting beside the
 * file are deleted, and nothing is left half-removed.
 */
@Composable
private fun UndoBar(host: AppHost, snackbars: SnackbarHostState) {
    val removed = host.removed.value
    val message = removed?.let { stringResource(R.string.downloads_removed, it.download.title) }
    val action = stringResource(R.string.downloads_undo)

    LaunchedEffect(removed) {
        if (removed == null || message == null) return@LaunchedEffect
        val outcome = snackbars.showSnackbar(
            message = message,
            actionLabel = action,
            duration = SnackbarDuration.Short,
        )
        // Another removal may have replaced this one while the bar was up; that removal owns
        // the state now, and settling on its behalf would delete bytes it is still offering.
        if (host.removed.value !== removed) return@LaunchedEffect
        if (outcome == SnackbarResult.ActionPerformed) {
            host.downloads.value = removed.undo(host.downloads.value)
        } else {
            removed.settle()
        }
        host.removed.value = null
        host.library.refreshImports()
    }
}

/**
 * Takes a download off the device, reversibly.
 *
 * The record goes now, so the shelf stops calling it downloaded; the bytes are moved aside
 * and only deleted when the undo window closes. [removeAfterFinishing] is named for the
 * sweep that first needed it and is the general act: a file already deleted can only be put
 * back by downloading it again, which is not an undo.
 */
private suspend fun remove(host: AppHost, download: Download) {
    val store = host.dependencies.downloads
    val outcome = removeAfterFinishing(store, host.downloads.value, download.id)
    if (outcome == null) {
        // Nothing on disk to move aside — a record whose file the system reclaimed.
        // Forgetting it is the whole removal, and there is nothing to undo.
        host.downloads.value = host.downloads.value.removing(download.id)
        store.save(host.downloads.value)
        host.library.refreshImports()
        return
    }
    host.removed.value?.settle()
    host.downloads.value = outcome.first
    host.removed.value = outcome.second
    // The library holds a row for every imported copy, and a row whose file has just been
    // moved aside is a book that opens onto nothing.
    host.library.refreshImports()
}

/** One full-width row inside the cover grid. */
private fun LazyGridScope.wide(content: @Composable () -> Unit) =
    item(span = { GridItemSpan(maxLineSpan) }) { content() }

@Composable
private fun DestinationTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.displaySmall,
        color = LocalStoryArcPalette.current.textPrimary,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun SectionHeading(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleLarge,
        color = LocalStoryArcPalette.current.textPrimary,
    )
}

/** What the files weigh, stated once and quietly. */
@Composable
private fun SpaceUsed(size: String) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = StoryArcSpace.md),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = stringResource(R.string.downloads_total),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
        Text(
            text = size,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
    }
}
