package app.storyarc

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.feature.library.LibraryScreen
import app.storyarc.navigation.AppDestination
import app.storyarc.navigation.AppSheet
import app.storyarc.navigation.Screen
import kotlinx.coroutines.launch

/**
 * The root of a destination — what is on screen when nothing is stacked on it.
 *
 * Exhaustive over the three, which is the property the whole rewrite exists to have: there
 * is no fourth branch, no combination of flags, and nothing a configured source can add.
 */
@Composable
internal fun Destination(host: AppHost, destination: AppDestination) {
    when (destination) {
        AppDestination.HOME -> HomeDestination(host)
        AppDestination.LIBRARY -> LibraryDestination(host)
        AppDestination.DOWNLOADS -> DownloadsDestination(host)
    }
}

/** The whole library, unchanged by this slice beyond the frame it now sits in. */
@Composable
private fun LibraryDestination(host: AppHost) {
    val dependencies = host.dependencies
    LibraryScreen(
        viewModel = host.library,
        onOpen = host.open,
        onOpenSettings = {
            // Re-read on the way in, so a download made since the last look is on the
            // screen rather than one visit behind it.
            host.downloads.value = dependencies.downloads.library()
            host.navigate { push(Screen.Settings()) }
        },
        onBrowse = { source -> host.browse(source, "") },
        // `kavita-server`: a search within a Kavita source goes to the server. The library's
        // own field filters the local index; this carries the question across, and the
        // browser opens with it.
        onSearchOnServer = { source, term -> host.browse(source, term) },
        onAddCatalogue = { host.sheet(AppSheet.AddOnlineLibrary) },
        onAddKavita = { host.sheet(AppSheet.AddKavita) },
        onAddShare = { host.sheet(AppSheet.AddSharedFolder) },
        onProbeSources = {
            // Asks every source once and then keeps asking while anything is away, per
            // `sources`' backoff. Stopped when the library leaves the screen, which is when
            // nobody is looking at the answer.
            host.library.retryUnreachableSources(dependencies.credentials, dependencies.pins)
        },
        onMark = { publication, isRead ->
            host.library.mark(
                publication,
                isRead,
                dependencies.kavitaProgress,
                dependencies.credentials,
            )
        },
        onRemoveSource = { host.library.removeSource(it, dependencies.credentials) },
        removedDownload = host.removed.value?.download?.title,
        onUndoRemoval = {
            host.activity.lifecycleScope.launch {
                host.removed.value?.let { host.downloads.value = it.undo(host.downloads.value) }
                host.removed.value = null
            }
        },
        onAddToServerList = { publication, list ->
            host.library.addToServerList(
                publication,
                list,
                dependencies.kavitaProgress,
                dependencies.credentials,
            )
        },
        onOpenShelves = { host.navigate { push(Screen.Shelves) } },
    )
}

/** Open the library at its root — the way out of an empty destination. */
internal fun AppHost.goToLibrary() {
    navigate { open(AppDestination.LIBRARY) }
}

/**
 * A destination's own frame: its large title, and the content under it.
 *
 * Material's `Scaffold` rather than a bare column, for the window insets alone — the
 * navigation shell has already taken the bottom one, and the status bar is still to pay
 * for. The flexible app bars the design direction asks for belong to the Home and Downloads
 * slices; what this owes them is a frame that is already correct about insets.
 */
@Composable
internal fun DestinationScaffold(title: String, content: LazyListScope.() -> Unit) {
    val palette = LocalStoryArcPalette.current
    Scaffold(containerColor = palette.surfaceCanvas) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = padding.calculateTopPadding() + StoryArcSpace.md,
                bottom = StoryArcSpace.xxl,
            ),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
        ) {
            item {
                Text(
                    text = title,
                    style = MaterialTheme.typography.displaySmall,
                    color = palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(horizontal = StoryArcSpace.gutter),
                )
            }
            content()
        }
    }
}

/**
 * A destination with nothing in it yet.
 *
 * One sentence and one action, composed by hand: Material publishes no empty-state
 * component, and importing iOS's `ContentUnavailableView` shape would be the port failure
 * this revamp exists to avoid. The destination stays present and selectable — one that
 * disappeared would teach a reader nothing.
 */
@Composable
internal fun EmptyDestination(sentence: String, onOpenLibrary: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xl),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
    ) {
        Text(
            text = sentence,
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
        )
        Button(onClick = onOpenLibrary) {
            Text(stringResource(R.string.destination_open_library))
        }
    }
}
