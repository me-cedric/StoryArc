package app.storyarc

import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download

/**
 * Everything readable with no network at all.
 *
 * `offline-downloads` makes this one of the three destinations rather than a page inside
 * Settings, and says why: a reader before a flight wants to see what they can read, not
 * what was fetched. This is the first cut of it — the destination exists, it is reachable
 * with no source consulted on the way, and it is complete in airplane mode. Presenting it
 * with the library's own grid and cells, and the queue controls above it, is the downloads
 * slice's work, not the shell's.
 */
@Composable
internal fun DownloadsDestination(host: AppHost) {
    // Nothing here removes a download. A removal is undoable for ten seconds and that undo
    // lives beside the library today; moving both is the downloads slice's work, and a
    // destructive action with no undo beside it would be worse than the trip to Settings.
    val context = LocalContext.current
    val library = host.downloads.value
    val publications by host.library.publications.collectAsStateWithLifecycle()

    // A download's identifier *is* the publication's, which is what lets one row be the
    // same book seen twice rather than two rows that happen to share a title.
    val open: (Download) -> Unit = { download ->
        publications.firstOrNull { it.id == download.id }?.let { publication ->
            host.library.location(publication)?.let { host.open(publication, it) }
        }
    }

    val inFlight = library.downloads.filterNot { it.state.isFinished }
    val onDevice = library.downloads.filter { it.state.isFinished }

    DestinationScaffold(title = stringResource(R.string.destination_downloads)) {
        if (library.downloads.isEmpty()) {
            item {
                EmptyDestination(
                    sentence = stringResource(R.string.downloads_destination_empty),
                    onOpenLibrary = { host.goToLibrary() },
                )
            }
            return@DestinationScaffold
        }

        // `offline-downloads`: when nothing is in flight the queue is absent rather than
        // shown empty, and the destination is just the readable library.
        if (inFlight.isNotEmpty()) {
            item { SectionHeading(stringResource(R.string.downloads_destination_in_flight)) }
            items(inFlight, key = { it.id }) { download ->
                DownloadRow(
                    title = download.title,
                    detail = Formatter.formatShortFileSize(context, download.downloadedBytes),
                    onOpen = null,
                )
            }
        }

        if (onDevice.isNotEmpty()) {
            item { SectionHeading(stringResource(R.string.downloads_destination_on_device)) }
            items(onDevice, key = { it.id }) { download ->
                DownloadRow(
                    title = download.title,
                    detail = Formatter.formatShortFileSize(
                        context,
                        download.expectedBytes ?: download.downloadedBytes,
                    ),
                    onOpen = { open(download) },
                )
            }
        }
    }
}

@Composable
private fun SectionHeading(text: String) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = text,
        style = MaterialTheme.typography.titleLarge,
        color = palette.textPrimary,
        modifier = Modifier.padding(horizontal = StoryArcSpace.gutter),
    )
}

@Composable
private fun DownloadRow(title: String, detail: String, onOpen: (() -> Unit)?) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onOpen == null) Modifier else Modifier.clickable(onClick = onOpen))
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = detail,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
    }
}
