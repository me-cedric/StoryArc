package app.storyarc.feature.library

import android.text.format.Formatter
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TextButton
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
import app.storyarc.core.smb.SmbError
import app.storyarc.core.smb.cacheLocation
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * A share, browsed folder by folder.
 *
 * A comic is read *over* the share rather than fetched from it: the ZIP and TAR readers work
 * through ranged reads over a `RandomAccessSource`, which is what ADR-0008 built them for,
 * and the reader resolves an `smb://` path through an opener the app registers. The first
 * page of a 400 MB archive costs a few megabytes.
 *
 * A PDF and a compressed RAR are the exceptions, and they are honest ones: `PdfRenderer` and
 * libarchive both want a real file, so those have to be copied down first -- and the copy is
 * *offered* rather than taken. `publication-formats` asks the app to say "the format has to be
 * downloaded before it can be read", state the size, and offer it; this screen used to fetch
 * four hundred megabytes in silence with `entry.length` already in hand. `ShareOpening.kt` is
 * where both decisions live, and iOS's `SmbBrowserView` decides them the same way.
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
    // `network-share`: on a metered connection the reader confirms before the app spends
    // their data. Held rather than acted on, because the answer is theirs to give.
    var confirming by remember(path) { mutableStateOf<SmbEntry?>(null) }
    // A publication the app cannot read where it lies, waiting for the reader to say whether
    // the whole file may come across. See [TransferAsk].
    var transferring by remember(path) { mutableStateOf<TransferAsk?>(null) }

    // Indexes from the share's own headers, then does what the offer says. The tap and the
    // metered confirmation both arrive here, so the decision is written once.
    //
    // Both decisions live in `ShareOpening.kt` rather than here, and that is the point: a JVM
    // gate can only read a composable as text, and `ShareOpeningTest` drives these two
    // functions with a publication of its choosing instead.
    fun openOrOffer(entry: SmbEntry) {
        scope.launch {
            opening = entry.path
            offerOrOpen(
                index = { indexOnShare(client, address, entry) },
                length = entry.length,
                onOpen = onOpen,
                onOffer = { bytes -> transferring = TransferAsk(entry, bytes) },
                onRefuse = { failure = R.string.detail_refused_body },
                onFailure = { failure = it },
            )
            opening = null
        }
    }

    // Reached only through the reader's own answer to [TransferAsk].
    fun transfer(entry: SmbEntry) {
        scope.launch {
            opening = entry.path
            openWhatArrived(
                fetch = { fetchAndIndex(context, client, address, entry) },
                onOpen = onOpen,
                onRefuse = { failure = R.string.detail_refused_body },
                onFailure = { failure = it },
            )
            opening = null
        }
    }

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
                    } else if (NetworkCost.isCareful(context)) {
                        confirming = entry
                    } else {
                        openOrOffer(entry)
                    }
                }
            }
        }
    }

    confirming?.let { entry ->
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text(stringResource(R.string.smb_metered_title)) },
            text = { Text(stringResource(R.string.smb_metered_body, entry.name)) },
            confirmButton = {
                TextButton(onClick = {
                    confirming = null
                    openOrOffer(entry)
                }) {
                    Text(stringResource(R.string.smb_metered_continue))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }

    // `publication-formats`, *Streaming capability per format*: a publication that cannot be
    // read with ranged reads gets a sentence, a size and an offer -- never a transfer the
    // reader did not ask for, and never a stalled page.
    transferring?.let { ask ->
        AlertDialog(
            onDismissRequest = { transferring = null },
            title = { Text(stringResource(R.string.smb_download_first_title)) },
            text = {
                Text(
                    // Two bodies, for `MeteredConfirmation`'s reason: a share that named no
                    // length is said in words rather than shown as `0 B`.
                    if (ask.bytes != null) {
                        stringResource(
                            R.string.smb_download_first_body,
                            ask.entry.name,
                            // The same call the metered confirmation, the Downloads
                            // destination and the storage rows already use.
                            Formatter.formatShortFileSize(context, ask.bytes),
                        )
                    } else {
                        stringResource(R.string.smb_download_first_body_unstated, ask.entry.name)
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    transferring = null
                    transfer(ask.entry)
                }) {
                    Text(stringResource(R.string.catalogue_acquire_download))
                }
            },
            dismissButton = {
                TextButton(onClick = { transferring = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

/**
 * What the reader is being asked to fetch before they can read it.
 *
 * A value rather than a flag, for [MeteredAsk]'s reason: the dialog names the publication and
 * states its size, and both have to survive being raised from inside the work that discovered
 * them. iOS's `TransferAsk` is the same record.
 */
private data class TransferAsk(
    val entry: SmbEntry,
    /**
     * What the share said the file weighs, or null when it said nothing worth repeating.
     * `publication-formats` requires the size to be stated and a directory entry is where it
     * comes from; [statedLength] is where an unusable one becomes an absence.
     */
    val bytes: Long?,
)

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

/**
 * Indexes a publication on the share, and says where it lives.
 *
 * Ranged reads over the share -- headers, not a file. Nothing is transferred here, which is
 * what lets the caller decide whether a transfer is worth offering at all, and state its size
 * while it asks.
 */
private suspend fun indexOnShare(
    client: SmbClient,
    address: SmbAddress,
    entry: SmbEntry,
): Pair<Publication, String> {
    val remotePath = "${SmbLocator.of(address)}/${entry.path}"
    val publication = PublicationIndexer.index(
        source = client.open(entry.path),
        name = entry.name,
        identity = PublicationIdentity(normalizedPath = remotePath),
    )
    return publication to remotePath
}

/**
 * Copies the whole publication down, and indexes it again from the copy.
 *
 * The second index is not a repetition: a solid archive's flag lives in headers libarchive
 * only reads through a path, so [Publication.streaming] is a guess over the share and an
 * answer once the file is here. The caller acts on the difference.
 */
private suspend fun fetchAndIndex(
    context: android.content.Context,
    client: SmbClient,
    address: SmbAddress,
    entry: SmbEntry,
): Pair<Publication, String> {
    val remotePath = "${SmbLocator.of(address)}/${entry.path}"
    val source = client.open(entry.path)

    val local = withContext(Dispatchers.IO) {
        val directory = File(context.cacheDir, "smb").apply { mkdirs() }
        // The server named this file. `cacheLocation` is what keeps its name from being a
        // place -- see `SmbEntry`.
        val destination = entry.cacheLocation(directory)
            ?: throw SmbError.Unexpected("unusable entry name")
        destination.apply {
            if (length() != entry.length) {
                writeBytes(source.read(0, entry.length.toInt()))
            }
        }
    }
    return PublicationIndexer.index(
        source = source,
        name = entry.name,
        identity = PublicationIdentity(normalizedPath = remotePath),
        decoderPath = local,
    ) to local.absolutePath
}
