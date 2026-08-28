package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbClient
import app.storyarc.core.smb.SmbEntry
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A share, browsed folder by folder.
 *
 * Opening a publication fetches the whole file first. That is not what `network-share` asks
 * for -- it wants the first page of a 400 MB archive without transferring 400 MB -- and the
 * pieces for the better answer are already here: the ZIP reader works through ranged reads
 * over a `RandomAccessSource`, which is what ADR-0008 built it for, and `SmbClient.open`
 * hands back exactly such a source. What is missing is a reader that takes one rather than a
 * path. Until it does, this downloads, and says so rather than pretending.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SmbBrowserScreen(
    title: String,
    address: SmbAddress,
    path: String,
    onEnter: (String) -> Unit,
    onOpen: (Publication, String) -> Unit,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val client = remember(address) { SmbClient(address) }
    var entries by remember(path) { mutableStateOf<List<SmbEntry>>(emptyList()) }
    // The string is resolved in the body rather than here: a resource read off
    // `LocalContext` is not configuration-aware, so what is kept is which message, not its
    // text at the moment it happened.
    var failure by remember(path) { mutableStateOf<Int?>(null) }
    var opening by remember(path) { mutableStateOf<String?>(null) }

    LaunchedEffect(path) {
        // On IO: the first call is what builds jcifs' context, and that blocks.
        runCatching { withContext(Dispatchers.IO) { client.list(path) } }
            .onSuccess { entries = it; failure = null }
            .onFailure { failure = R.string.smb_error_unexpected }
    }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = path.substringAfterLast('/').ifEmpty { title },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.catalogue_back),
                            tint = palette.accent,
                        )
                    }
                },
            )
        },
    ) { insets ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(StoryArcSpace.gutter),
        ) {
            failure?.let { message ->
                item {
                    Text(
                        text = stringResource(message),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textSecondary,
                    )
                }
            }
            items(entries, key = { it.path }) { entry ->
                EntryRow(entry, isOpening = opening == entry.path) {
                    if (entry.isDirectory) {
                        onEnter(entry.path)
                    } else {
                        scope.launch {
                            opening = entry.path
                            runCatching { openFromShare(context, client, address, entry) }
                                .onSuccess { (publication, decoder) ->
                                    onOpen(publication, decoder)
                                }
                                // Said out loud rather than swallowed. A tap that does
                                // nothing is the worst answer a screen can give.
                                .onFailure { failure = R.string.smb_error_unexpected }
                            opening = null
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EntryRow(entry: SmbEntry, isOpening: Boolean, onTap: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !isOpening, onClick = onTap)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs)
            .semantics(mergeDescendants = true) { contentDescription = entry.name },
    ) {
        Icon(
            imageVector = if (entry.isDirectory) {
                Icons.Filled.Folder
            } else {
                Icons.AutoMirrored.Filled.MenuBook
            },
            contentDescription = null,
            tint = palette.textSecondary,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(entry.name, style = MaterialTheme.typography.bodyLarge, color = palette.textPrimary)
        }
        if (isOpening) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(2.dp))
        }
    }
}

/** Fetches a publication from the share and indexes it. */
private suspend fun openFromShare(
    context: android.content.Context,
    client: SmbClient,
    address: SmbAddress,
    entry: SmbEntry,
): Pair<Publication, String> {
    val source = client.open(entry.path)
    val identity = PublicationIdentity(
        normalizedPath = "${SmbLocator.of(address)}/${entry.path}",
    )
    // A local copy for the decoders that insist on a path. `offline-downloads` owns keeping
    // things on the device; this is the cache, and it is the reader's working copy.
    val local = withContext(Dispatchers.IO) {
        val directory = File(context.cacheDir, "smb").apply { mkdirs() }
        File(directory, entry.name).apply {
            if (length() != entry.length) {
                writeBytes(source.read(0, entry.length.toInt()))
            }
        }
    }
    val publication = PublicationIndexer.index(
        source = source,
        name = entry.name,
        identity = identity,
        decoderPath = local,
    )
    return publication to local.absolutePath
}
