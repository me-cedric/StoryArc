package app.storyarc.feature.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import java.text.DateFormat
import kotlinx.coroutines.launch

/**
 * What a catalogue says about one publication, and every way it offers to get it.
 *
 * `opds-catalog`: the app "selects EPUB for reflowable reading and lets the user choose
 * another format from the publication detail screen". This is that screen. Until it existed
 * the choice lived in a long-press menu -- a place a reader has to already know about,
 * offering a decision with none of the context needed to make it.
 *
 * The art leads, per the project's rule that the artwork is the interface: the cover at a
 * size worth looking at, and the metadata under it in the order a reader asks for it. iOS's
 * `CatalogueDetailView` is the same screen.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun CatalogueDetailScreen(
    entry: OpdsEntry,
    credential: OpdsCredential?,
    /** The page's client, so the cover comes down behind the same credential the feed did. */
    client: OpdsClient,
    queue: DownloadQueue,
    onOpen: (Publication, String) -> Unit,
    onBack: () -> Unit = {},
) {
    val palette = LocalStoryArcPalette.current
    val downloads by queue.library.collectAsStateWithLifecycle()
    val isDownloaded = downloads.finished.any { it.id == entry.id }
    val active = downloads.pending
    val scope = rememberCoroutineScope()
    var cover by remember(entry.id) { mutableStateOf<Bitmap?>(null) }

    // The full-size cover, not the thumbnail the grid settled for.
    LaunchedEffect(entry.id) {
        val href = entry.cover ?: entry.thumbnail ?: return@LaunchedEffect
        val bytes = runCatching { client.bytes(href, credential) }.getOrNull()
            ?: return@LaunchedEffect
        cover = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    }

    val take: (OpdsAcquisition) -> Unit = { link ->
        scope.launch { openWhenReady(queue, entry, link, onOpen) }
    }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = {
                    Text(text = entry.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
        Column(modifier = Modifier.fillMaxSize().padding(insets)) {
            Column(
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(StoryArcSpace.gutter),
            ) {
                Artwork(entry, cover)

                Headline(entry, isDownloaded)

                CatalogueFormatChoice(
                    entry = entry,
                    isDownloaded = isDownloaded,
                    onTake = take,
                    onRead = { CatalogueAcquisition.best(entry)?.let(take) },
                    onRemove = { queue.remove(entry.id) },
                )

                entry.summary?.takeIf { it.isNotBlank() }?.let { summary ->
                    Text(
                        text = summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textSecondary,
                    )
                }

                entry.updated?.let { updated ->
                    // Read through `LocalConfiguration`, which recomposes when the
                    // configuration changes: `settings-and-about` lets a reader
                    // override the language in place, and a date read off the
                    // context would still be in the old one.
                    val locale = LocalConfiguration.current.locales[0]
                    Text(
                        text = stringResource(
                            R.string.catalogue_detail_updated,
                            DateFormat.getDateInstance(DateFormat.MEDIUM, locale).format(updated),
                        ),
                        style = MaterialTheme.typography.labelSmall,
                        color = palette.textTertiary,
                    )
                }
            }

            active.firstOrNull()?.let { first ->
                DownloadBanner(
                    download = first,
                    others = active.size - 1,
                    onCancel = { queue.cancel(first.id) },
                    onResume = { queue.resume(first.id) },
                )
            }
        }
    }
}

/**
 * The cover, large, with the title standing in for one that never arrives.
 *
 * Capped rather than full-bleed: a 2:3 cover across a tablet is a cover nobody can see the
 * whole of without scrolling, and the metadata under it is the point of the screen.
 */
@Composable
private fun Artwork(entry: OpdsEntry, cover: Bitmap?) {
    val palette = LocalStoryArcPalette.current
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .widthIn(max = 240.dp)
                .aspectRatio(2f / 3f)
                .clip(RoundedCornerShape(StoryArcRadius.lg))
                // Decorative: the title is read out of the headline below, and a screen
                // reader announcing it twice reads as a stutter.
                .clearAndSetSemantics {},
        ) {
            if (cover != null) {
                Image(
                    bitmap = cover.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    Text(
                        text = entry.title,
                        style = MaterialTheme.typography.titleMedium,
                        color = palette.textSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(StoryArcSpace.md),
                    )
                }
            }
        }
    }
}

/** Title, authors, series -- the publication's own metadata, as the feed reports it. */
@Composable
private fun Headline(entry: OpdsEntry, isDownloaded: Boolean) {
    val palette = LocalStoryArcPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
        if (isDownloaded) {
            Text(
                text = stringResource(R.string.catalogue_entry_downloaded),
                style = MaterialTheme.typography.labelSmall,
                color = palette.accent,
            )
        }

        Text(
            text = entry.title,
            style = MaterialTheme.typography.headlineSmall,
            color = palette.textPrimary,
        )

        if (entry.authors.isNotEmpty()) {
            Text(
                text = entry.authors.joinToString(", "),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
        }

        // Written rather than localised: a series name and a number joined by a hash is the
        // same in every language this app speaks.
        entry.series?.let { series ->
            Text(
                text = entry.seriesIndex?.let { "$series #${it.toInt()}" } ?: series,
                style = MaterialTheme.typography.labelMedium,
                color = palette.textTertiary,
            )
        }
    }
}

/**
 * Every way this catalogue offers a publication, as a choice rather than a menu.
 *
 * `opds-catalog` names two things this has to do at once. It "selects EPUB for reflowable
 * reading and lets the user choose another format", so the default is one press and the
 * alternatives are visible without hunting; and where nothing is readable the entry is
 * "listed but marked unreadable, naming the formats offered", so the refusal names what was
 * on offer rather than leaving a dead screen.
 */
@Composable
private fun CatalogueFormatChoice(
    entry: OpdsEntry,
    isDownloaded: Boolean,
    onTake: (OpdsAcquisition) -> Unit,
    onRead: () -> Unit,
    onRemove: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val offered = CatalogueAcquisition.readable(entry)
    val unreadable = CatalogueAcquisition.unreadable(entry)
    val unsupported = CatalogueAcquisition.unsupported(entry)

    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        if (offered.isNotEmpty()) {
            Button(onClick = onRead, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.catalogue_detail_read))
            }

            if (isDownloaded) {
                OutlinedButton(onClick = onRemove, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.downloads_remove))
                }
            }

            Text(
                text = stringResource(R.string.catalogue_detail_formats),
                style = MaterialTheme.typography.labelSmall,
                color = palette.textSecondary,
            )

            offered.forEachIndexed { position, link ->
                FormatRow(link, isDefault = position == 0) { onTake(link) }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
            if (unreadable.isNotEmpty()) {
                Text(
                    text = stringResource(
                        R.string.catalogue_entry_unreadable,
                        unreadable.joinToString(", "),
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.textSecondary,
                )
            }

            // `opds-catalog`: a borrow or an OPDS-LCP flow makes the app "state that the
            // acquisition type is not supported rather than failing silently". One line per
            // kind, because a catalogue that offers both a loan and a purchase has refused
            // the reader twice for two different reasons.
            unsupported.forEach { kind ->
                Text(
                    text = stringResource(
                        R.string.catalogue_detail_unsupported,
                        stringResource(kind.nameResource()),
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.textSecondary,
                )
            }

            if (offered.isEmpty() && unreadable.isEmpty() && unsupported.isEmpty()) {
                Text(
                    text = stringResource(R.string.catalogue_entry_no_download),
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.textSecondary,
                )
            }
        }
    }
}

/** One format, said to be the default where it is the one a press would take. */
@Composable
private fun FormatRow(link: OpdsAcquisition, isDefault: Boolean, onTake: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Surface(
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.md),
        onClick = onTake,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(StoryArcSpace.md),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = PublicationFormat.ofMediaType(link.mediaType)?.displayName
                        ?: link.mediaType,
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.textPrimary,
                )
                if (isDefault) {
                    Text(
                        text = stringResource(R.string.catalogue_detail_default),
                        style = MaterialTheme.typography.labelSmall,
                        color = palette.textSecondary,
                    )
                }
            }
        }
    }
}

/** How an acquisition the app refuses is named in the sentence that refuses it. */
private fun OpdsAcquisition.Kind.nameResource(): Int = when (this) {
    OpdsAcquisition.Kind.BORROW -> R.string.catalogue_acquire_kind_borrow
    OpdsAcquisition.Kind.BUY -> R.string.catalogue_acquire_kind_buy
    OpdsAcquisition.Kind.SUBSCRIBE -> R.string.catalogue_acquire_kind_subscribe
    OpdsAcquisition.Kind.OPEN,
    OpdsAcquisition.Kind.DIRECT,
    OpdsAcquisition.Kind.SAMPLE,
    OpdsAcquisition.Kind.INDIRECT,
    -> R.string.catalogue_acquire_kind_indirect
}

/**
 * Waits for a download and opens it.
 *
 * Separate from the press so the press returns immediately: `offline-downloads` wants a
 * publication that is still downloading to be openable, and a handler that blocks is a
 * handler nothing else can happen during. An already-downloaded publication opens from disk,
 * which also means it opens with no network at all.
 */
internal suspend fun openWhenReady(
    queue: DownloadQueue,
    entry: OpdsEntry,
    link: OpdsAcquisition,
    onOpen: (Publication, String) -> Unit,
) {
    val file = queue.downloaded(entry) ?: queue.fetch(entry, link) ?: return
    runCatching { PublicationIndexer.index(file, catalogueSeries = entry.series) }
        .getOrNull()
        ?.let { onOpen(it, file.absolutePath) }
}
