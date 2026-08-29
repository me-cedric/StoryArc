package app.storyarc.feature.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * One publication in a catalogue, before it is on the device.
 *
 * `opds-catalog` requires an entry offering only unsupported formats to be "listed but marked
 * unreadable, naming the formats offered", which is a state a local publication never has.
 *
 * A tap opens the detail screen rather than starting a download. The spec puts the choice of
 * format "on the publication detail screen", and a cell where the tap committed to a format
 * left the reader nowhere to make it -- the choice lived in the long-press menu, which is a
 * place readers do not look. iOS's `CatalogueEntryCell` is the same cell.
 */
// `combinedClickable` is still experimental and is the only way to have a tap and a long
// press on one surface. Opted in here, where the long press is the menu.
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun CatalogueEntryCell(
    entry: OpdsEntry,
    credential: OpdsCredential?,
    /** The page's client, not one of this cell's own. */
    client: OpdsClient,
    /** Whether this one is already on the device. */
    isDownloaded: Boolean,
    onSelect: () -> Unit,
    onDownload: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var menu by remember { mutableStateOf(false) }
    var cover by remember(entry.id) { mutableStateOf<Bitmap?>(null) }

    // Fetched through the same client the feed came from: a private catalogue's covers sit
    // behind the same credential, and an image loader has nowhere to put one.
    LaunchedEffect(entry.id) {
        val href = entry.thumbnail ?: entry.cover ?: return@LaunchedEffect
        val bytes = runCatching { client.bytes(href, credential) }.getOrNull()
            ?: return@LaunchedEffect
        cover = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    }

    val describes = subtitle(entry, CatalogueAcquisition.readable(entry))
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = modifier
            .combinedClickable(
                onClick = onSelect,
                // A long press is where Android puts "what else can I do with this". What it
                // keeps is the shortcut, not the decision: `offline-downloads` wants a reader
                // packing for a flight to take the download without the reading.
                onLongClick = { menu = true },
            )
            // Merged and named. `Modifier.clickable` makes a node a screen reader can reach
            // and does not pull the title into it, so every cell announced itself as an
            // unnamed button — which `pnpm a11y:android` found and a screenshot could not.
            .semantics(mergeDescendants = true) {
                contentDescription = listOf(entry.title, describes)
                    .filter { it.isNotEmpty() }
                    .joinToString(". ")
            },
    ) {
        Surface(
            color = palette.surfaceRaised,
            shape = RoundedCornerShape(StoryArcRadius.md),
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
        ) {
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(StoryArcRadius.md)),
                )
            } else {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = entry.title,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.textSecondary,
                        textAlign = TextAlign.Center,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
                    )
                }
            }
        }

        // `offline-downloads`: a downloaded publication shows "a state indicator" rather than
        // an action to download it again.
        if (isDownloaded) {
            Text(
                text = stringResource(R.string.catalogue_entry_downloaded),
                style = MaterialTheme.typography.labelSmall,
                color = palette.accent,
            )
        }

        Text(
            text = entry.title,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = describes,
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            if (isDownloaded) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.downloads_remove)) },
                    onClick = {
                        menu = false
                        onRemove()
                    },
                )
            } else if (CatalogueAcquisition.best(entry) != null) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.catalogue_acquire_download)) },
                    onClick = {
                        menu = false
                        onDownload()
                    },
                )
            }
        }
    }
}

/** The author, or -- when nothing here can be opened -- what was offered instead. */
@Composable
private fun subtitle(entry: OpdsEntry, offered: List<OpdsAcquisition>): String {
    if (offered.isNotEmpty()) {
        val series = entry.series
        val index = entry.seriesIndex
        return when {
            series != null && index != null -> "$series #${index.toInt()}"
            series != null -> series
            else -> entry.authors.firstOrNull().orEmpty()
        }
    }
    val types = CatalogueAcquisition.unreadable(entry)
    return if (types.isEmpty()) {
        stringResource(R.string.catalogue_entry_no_download)
    } else {
        stringResource(R.string.catalogue_entry_unreadable, types.joinToString(", "))
    }
}
