package app.storyarc.feature.library

import androidx.compose.foundation.clickable
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

    LaunchedEffect(series.id) {
        volumes = runCatching { client.volumes(series.id) }.getOrDefault(emptyList())
        // Each on its own, because a server that cannot answer one of the three should still
        // show the other two rather than an empty screen.
        metadata = runCatching { client.metadata(series.id) }.getOrNull()
        resume = runCatching { client.continuePoint(series.id) }.getOrNull()
    }

    val open: (KavitaChapter) -> Unit = { chapter ->
        scope.launch {
            fetching = chapter.id
            fetch(context, client, series.name, chapter)?.let { (publication, path) ->
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
                ChapterRow(chapter, isFetching = fetching == chapter.id) { open(chapter) }
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
private fun ChapterRow(chapter: KavitaChapter, isFetching: Boolean, onOpen: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    // The tick means "finished" and the spinner means "fetching". Both are silent to a
    // screen reader unless the row says so itself.
    val state = when {
        isFetching -> stringResource(R.string.kavita_fetching)
        chapter.isFinished -> stringResource(R.string.library_read_state_finished)
        else -> null
    }
    val spoken = state?.let { "${chapter.displayName}, $it" } ?: chapter.displayName
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = !isFetching, onClick = onOpen)
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
    val bytes = client.chapter(chapter.id)
    val file = withContext(Dispatchers.IO) {
        val directory = File(context.cacheDir, "kavita").apply { mkdirs() }
        File(directory, "chapter-${chapter.id}.cbz").apply { writeBytes(bytes) }
    }
    PublicationIndexer.index(file, seriesName) to file.absolutePath
}.getOrNull()
