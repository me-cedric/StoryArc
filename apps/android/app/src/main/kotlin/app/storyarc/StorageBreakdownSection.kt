package app.storyarc

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.bytesBySource
import app.storyarc.core.model.largestFirst

/**
 * What the files weigh, broken down.
 *
 * `offline-downloads` asks the storage view to state the total "broken down by source", to
 * offer "a largest-first list, each removable", and to state "the cover cache size" beside
 * the downloads total. Until now this row said only the one number. iOS's
 * `StorageBreakdownSection` is the same view.
 */
@Composable
internal fun StorageBreakdownSection(
    /**
     * What the app's own downloads directory weighs, asked of the filesystem by the caller
     * for the reason it always is: the system can reclaim a download, and a total counting
     * bytes nobody has is the kind of number that makes a reader distrust the screen.
     */
    totalBytes: Long,
    /**
     * What the cover cache alone is holding -- distinct from the total above, which it is
     * not part of.
     */
    coverCacheBytes: Long,
    /** What is on the device and what is still on its way, for the breakdowns below. */
    downloads: DownloadLibrary,
    /** Where each download's source is named. */
    registry: SourceRegistry,
    /** Removes one finished download, through the same confirmation the shelf's own does. */
    onRemove: (Download) -> Unit,
) {
    val context = LocalContext.current
    val palette = LocalStoryArcPalette.current

    fun size(bytes: Long) = Formatter.formatShortFileSize(context, bytes)

    Column(
        modifier = Modifier.fillMaxWidth().padding(top = StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        StatRow(stringResource(R.string.downloads_total), size(totalBytes))
        bySource(downloads, registry).forEach { (name, bytes) -> StatRow(name, size(bytes)) }
        StatRow(stringResource(R.string.downloads_cache), size(coverCacheBytes))

        val largest = downloads.largestFirst.take(LARGEST_COUNT)
        if (largest.isNotEmpty()) {
            Text(
                text = stringResource(R.string.downloads_largest),
                style = MaterialTheme.typography.labelSmall,
                color = palette.textSecondary,
                modifier = Modifier.padding(top = StoryArcSpace.sm),
            )
            largest.forEach { download ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                ) {
                    Text(
                        text = download.title,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = size(download.downloadedBytes),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textSecondary,
                    )
                    IconButton(onClick = { onRemove(download) }) {
                        Icon(
                            imageVector = Icons.Filled.Delete,
                            contentDescription = stringResource(
                                R.string.downloads_remove_action,
                                download.title,
                            ),
                            tint = palette.textSecondary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StatRow(title: String, value: String) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(text = title, style = MaterialTheme.typography.bodyMedium, color = palette.textSecondary)
        Text(text = value, style = MaterialTheme.typography.bodyMedium, color = palette.textSecondary)
    }
}

/**
 * The total broken down by source, named and ordered largest first.
 *
 * A download with no source of its own, or one whose source has since been removed, is
 * left out rather than named "null" -- the total above already counts it.
 */
private fun bySource(downloads: DownloadLibrary, registry: SourceRegistry): List<Pair<String, Long>> =
    downloads.bytesBySource.entries
        .mapNotNull { (sourceId, bytes) -> registry[sourceId ?: return@mapNotNull null]?.displayName?.let { it to bytes } }
        .sortedByDescending { it.second }

private const val LARGEST_COUNT = 10
