package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaMetadata
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.kavita.KavitaVolume
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.persistence.KavitaCardStore
import app.storyarc.core.persistence.KavitaOrigin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import app.storyarc.core.model.ProgressPull
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.persistence.KavitaProgressStore
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * One series: what the server says about it, where to resume, and every chapter.
 *
 * `kavita-server` asks for three things here -- the server's own metadata preferred over the
 * file's, volumes and loose chapters distinguished, and a "Continue" primary action pointing
 * at the chapter Kavita reports as next.
 */
@Composable
fun KavitaChapters(
    series: KavitaSeries,
    client: KavitaClient,
    sourceId: String,
    store: KavitaProgressStore,
    /** Where a pulled position is written. Null in a preview, which has no store to merge into. */
    progress: ProgressStore? = null,
    /** This server's own reading lists, which its chapters may be added to. */
    lists: List<ServerList> = emptyList(),
    onOpen: (Publication, String) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(0.dp),
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val palette = LocalStoryArcPalette.current

    var volumes by remember(series.id) { mutableStateOf<List<KavitaVolume>>(emptyList()) }
    var metadata by remember(series.id) { mutableStateOf<KavitaMetadata?>(null) }
    var resume by remember(series.id) { mutableStateOf<KavitaChapter?>(null) }
    var fetching by remember(series.id) { mutableStateOf<Int?>(null) }
    var conflicts by remember(series.id) { mutableStateOf<List<ProgressPull.Conflict>>(emptyList()) }

    // Which chapters this device already has a download of. Seeded from the cards rather than
    // from the download library: a card names the chapter a download came from, and the
    // download record is keyed on a publication identity that only exists once the file has
    // been indexed.
    var kept by remember(series.id) { mutableStateOf<Set<Int>>(emptySet()) }

    LaunchedEffect(series.id) {
        kept = KavitaCardStore.open(context).all(sourceId).map { it.chapterId }.toSet()
    }

    LaunchedEffect(series.id) {
        volumes = runCatching { client.volumes(series.id) }.getOrDefault(emptyList())
        // Each on its own, because a server that cannot answer one of the three should still
        // show the other two rather than an empty screen.
        metadata = runCatching { client.metadata(series.id) }.getOrNull()
        resume = runCatching { client.continuePoint(series.id) }.getOrNull()
        // `reading-progress`: "when a synchronising source refreshes, progress recorded on
        // other devices is merged into the local store". This is that refresh -- the
        // chapters have just arrived carrying what the server thinks has been read.
        progress?.let { store2 ->
            conflicts = KavitaSync.pull(
                volumes.flatMap { it.chapters },
                store,
                store2,
                sourceId,
                client.address,
            )
        }
    }

    // `reading-progress`: a genuine conflict is one the reader "is told once -- naming both
    // -- with the option to take the other". Once, not per chapter: a server that has moved
    // on in six places is one thing that happened, and six dialogs about it would be the app
    // making a reader dismiss its own synchronisation.
    if (conflicts.isNotEmpty()) {
        val discarded = conflicts
        AlertDialog(
            onDismissRequest = { conflicts = emptyList() },
            title = { Text(stringResource(R.string.sync_conflict_title)) },
            text = { Text(stringResource(R.string.sync_conflict_body, discarded.size)) },
            confirmButton = {
                TextButton(onClick = { conflicts = emptyList() }) {
                    Text(stringResource(R.string.sync_conflict_keep))
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        conflicts = emptyList()
                        // Taking the other means writing back what was set aside -- the
                        // reader saying the further position was not theirs.
                        scope.launch {
                            discarded.forEach { conflict ->
                                progress?.save(
                                    conflict.resolved.copy(position = conflict.discarded),
                                )
                            }
                        }
                    },
                ) {
                    Text(stringResource(R.string.sync_conflict_take))
                }
            },
        )
    }

    // `kavita-server`: marking read must reach the server so its own UI agrees. A long
    // press is where Android puts "what else can I do with this".
    fun originOf(chapter: KavitaChapter) = KavitaOrigin(
        sourceId = sourceId,
        libraryId = series.libraryId,
        seriesId = series.id,
        volumeId = volumes.firstOrNull { volume ->
            volume.chapters.any { it.id == chapter.id }
        }?.id ?: 0,
        chapterId = chapter.id,
    )

    val mark: (KavitaChapter, Boolean) -> Unit = { chapter, isRead ->
        scope.launch {
            KavitaSync.mark(store, client.address, originOf(chapter), isRead)
            volumes = runCatching { client.volumes(series.id) }.getOrDefault(volumes)
        }
    }

    // `kavita-server` has a scenario about opening "a downloaded Kavita publication" offline,
    // and until this there was no way to have one: the browser wrote every chapter to the
    // cache directory. This is the asking. The chapter is not opened afterwards -- keeping is
    // a different act from reading, and jumping into the reader would answer a question
    // nobody put.
    val keep: (KavitaChapter) -> Unit = { chapter ->
        scope.launch {
            fetching = chapter.id
            val done = KavitaKeep.keep(
                context = context,
                chapter = chapter,
                series = series,
                metadata = metadata,
                origin = originOf(chapter),
                sourceId = runCatching { java.util.UUID.fromString(sourceId) }.getOrNull(),
                client = client,
            )
            if (done != null) kept = kept + chapter.id
            fetching = null
        }
    }

    val addTo: (KavitaChapter, ServerList) -> Unit = { chapter, list ->
        scope.launch { KavitaSync.append(store, client.address, originOf(chapter), list.id) }
    }

    val open: (KavitaChapter) -> Unit = { chapter ->
        scope.launch {
            fetching = chapter.id
            fetch(context, client, series.name, chapter)?.let { (publication, path) ->
                // The note the reader cannot leave for itself: it opens a file and knows
                // nothing about servers, so this is what lets the position get home.
                store.remember(
                    publication.id,
                    KavitaOrigin(
                        sourceId = sourceId,
                        libraryId = series.libraryId,
                        seriesId = series.id,
                        volumeId = volumes.firstOrNull { volume ->
                            volume.chapters.any { it.id == chapter.id }
                        }?.id ?: 0,
                        chapterId = chapter.id,
                    ),
                )
                onOpen(publication, path)
            }
            fetching = null
        }
    }

    LazyColumn(modifier = modifier, contentPadding = contentPadding) {
        resume?.let { next ->
            item(key = "continue") {
                Button(
                    onClick = { open(next) },
                    enabled = fetching == null,
                    modifier = Modifier.fillMaxWidth().padding(bottom = StoryArcSpace.md),
                ) {
                    Text(stringResource(R.string.kavita_continue, next.displayName))
                }
            }
        }

        metadata?.let { held -> item(key = "metadata") { KavitaMetadataBlock(held) } }

        volumes.forEach { volume ->
            item(key = "volume-${volume.id}") {
                // Loose chapters are not a volume, and labelling them as one would invent a
                // "Volume 0" the server never had.
                Text(
                    text = if (volume.isLooseChapters) {
                        stringResource(R.string.kavita_loose_chapters)
                    } else {
                        volume.name ?: volume.number.toString()
                    },
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                    modifier = Modifier.padding(vertical = StoryArcSpace.xs),
                )
            }
            items(volume.chapters, key = { it.id }) { chapter ->
                ChapterRow(
                    chapter = chapter,
                    isFetching = fetching == chapter.id,
                    isKept = chapter.id in kept,
                    // Only this server's own lists: a Kavita list can hold nothing else,
                    // and offering another server's would be offering a refusal.
                    lists = lists.filter { it.server.id == sourceId },
                    onOpen = { open(chapter) },
                    onKeep = { keep(chapter) },
                    onMark = { mark(chapter, !chapter.isFinished) },
                    onAddTo = { addTo(chapter, it) },
                )
            }
        }
    }
}

/** The server's own description of a series, which wins over anything inside the file. */
@Composable
private fun KavitaMetadataBlock(metadata: KavitaMetadata) {
    val palette = LocalStoryArcPalette.current
    val facts = buildList {
        metadata.releaseYear.takeIf { it > 0 }?.let { add(it.toString()) }
        addAll(metadata.people)
        addAll(metadata.subjects)
    }
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier.padding(bottom = StoryArcSpace.md),
    ) {
        metadata.summary?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = palette.textPrimary)
        }
        if (facts.isNotEmpty()) {
            Text(
                text = facts.joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
}

@Composable
private fun ChapterRow(
    chapter: KavitaChapter,
    isFetching: Boolean,
    isKept: Boolean,
    lists: List<ServerList>,
    onOpen: () -> Unit,
    onKeep: () -> Unit,
    onMark: () -> Unit,
    onAddTo: (ServerList) -> Unit,
) {
    // A long press opens the choices rather than performing one, because there are two:
    // marking read, and putting the chapter in one of the server's lists.
    var menuOpen by remember { mutableStateOf(false) }
    val palette = LocalStoryArcPalette.current
    // The tick means "finished" and the spinner means "fetching". Both are silent to a
    // screen reader unless the row says so itself.
    val state = when {
        isFetching -> stringResource(R.string.kavita_fetching)
        chapter.isFinished -> stringResource(R.string.library_read_state_finished)
        isKept -> stringResource(R.string.kavita_kept)
        else -> null
    }
    val spoken = state?.let { "${chapter.displayName}, $it" } ?: chapter.displayName
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(
                enabled = !isFetching,
                onClick = onOpen,
                onLongClick = { menuOpen = true },
                onLongClickLabel = stringResource(R.string.kavita_chapter_actions),
            )
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs)
            .semantics(mergeDescendants = true) { contentDescription = spoken },
    ) {
        Text(
            text = chapter.displayName,
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
            modifier = Modifier.weight(1f),
        )
        when {
            isFetching ->
                CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(2.dp))
            chapter.isFinished ->
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = palette.accent)
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.kavita_keep)) },
                enabled = !isKept,
                onClick = {
                    menuOpen = false
                    onKeep()
                },
            )
            DropdownMenuItem(
                text = {
                    Text(
                        stringResource(
                            if (chapter.isFinished) {
                                R.string.library_mark_unread
                            } else {
                                R.string.library_mark_read
                            },
                        ),
                    )
                },
                onClick = {
                    menuOpen = false
                    onMark()
                },
            )
            lists.forEach { list ->
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.kavita_add_to_list, list.title)) },
                    onClick = {
                        menuOpen = false
                        onAddTo(list)
                    },
                )
            }
        }
    }
}

/**
 * Fetches a chapter and indexes it.
 *
 * Into the cache directory, not the download store: `kavita-server` and `offline-downloads`
 * are different promises, and a chapter opened once is not a download the reader asked to
 * keep.
 */
private suspend fun fetch(
    context: android.content.Context,
    client: KavitaClient,
    seriesName: String,
    chapter: KavitaChapter,
): Pair<Publication, String>? = runCatching {
    val fetched = client.chapter(chapter.id)
    val file = withContext(Dispatchers.IO) {
        kavitaCacheFile(context, chapter.id, fetched.mediaType).apply { writeBytes(fetched.bytes) }
    }
    PublicationIndexer.index(file, catalogueSeries = seriesName) to file.absolutePath
}.getOrNull()

/**
 * Where a fetched chapter is written, named for what it actually is.
 *
 * `kavita-server` serves comics and books from the same endpoint, and the reader the app
 * opens is chosen by the file's format. Writing every chapter as `.cbz` sent an EPUB to the
 * comic reader, which spun for ever on a file it could not page.
 */
internal fun kavitaCacheFile(
    context: android.content.Context,
    chapterId: Int,
    mediaType: String?,
): File {
    val extension = mediaType
        ?.let { PublicationFormat.ofMediaType(it) }
        ?.name
        ?.lowercase()
        ?: "cbz"
    val directory = File(context.cacheDir, "kavita").apply { mkdirs() }
    return File(directory, "chapter-$chapterId.$extension")
}
