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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaLibraryFolder
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.kavita.KavitaVolume
import app.storyarc.core.model.Publication
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Where the reader is inside a Kavita server.
 *
 * A value rather than three screens with their own navigation, because the app layer already
 * owns navigation and a third scheme beside catalogues and collections would be a third thing
 * to get the back gesture wrong in.
 *
 * Owned by the app layer, not by the browser. The browser leaves the composition while a
 * chapter is open, so a level it remembered itself would be gone by the time the reader
 * closed the chapter -- which put them back at the list of libraries, two taps from the
 * series they had just been reading.
 */
sealed interface KavitaLevel {
    data object Libraries : KavitaLevel
    data class Series(val library: KavitaLibraryFolder) : KavitaLevel
    data class Chapters(val series: KavitaSeries) : KavitaLevel
}

/**
 * A Kavita server's libraries, its series, and the chapters inside them.
 *
 * `kavita-server` requires the app to mirror that structure rather than flatten it, so this
 * is three levels rather than one grid. iOS's `KavitaBrowserView` is the same three.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun KavitaBrowserScreen(
    title: String,
    address: KavitaAddress,
    level: KavitaLevel,
    onLevel: (KavitaLevel) -> Unit,
    onOpen: (Publication, String) -> Unit,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Created once, from the address. Rebuilt on every redraw it would forget its session
    // token and re-authenticate for each request.
    val client = remember(address) { KavitaClient(address) }

    var libraries by remember(address) { mutableStateOf<List<KavitaLibraryFolder>>(emptyList()) }
    var series by remember(address) { mutableStateOf<List<KavitaSeries>>(emptyList()) }
    var volumes by remember(address) { mutableStateOf<List<KavitaVolume>>(emptyList()) }
    var fetching by remember(address) { mutableStateOf<Int?>(null) }

    LaunchedEffect(client) {
        libraries = runCatching { client.libraries() }.getOrDefault(emptyList())
    }

    val current = level
    LaunchedEffect(current) {
        when (current) {
            is KavitaLevel.Series ->
                series = runCatching { client.series(current.library.id) }.getOrDefault(emptyList())
            is KavitaLevel.Chapters ->
                volumes = runCatching { client.volumes(current.series.id) }.getOrDefault(emptyList())
            is KavitaLevel.Libraries -> Unit
        }
    }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = when (current) {
                            is KavitaLevel.Libraries -> title
                            is KavitaLevel.Series -> current.library.name
                            is KavitaLevel.Chapters -> current.series.name
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        // Up one level, and out of the server only from the top. One gesture
                        // meaning two things, decided by where the reader is.
                        onLevel(
                            when (current) {
                                is KavitaLevel.Libraries -> return@IconButton onBack()
                                is KavitaLevel.Series -> KavitaLevel.Libraries
                                is KavitaLevel.Chapters ->
                                    libraries.firstOrNull { it.id == current.series.libraryId }
                                        ?.let(KavitaLevel::Series)
                                        ?: KavitaLevel.Libraries
                            },
                        )
                    }) {
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
            when (current) {
                is KavitaLevel.Libraries -> items(libraries, key = { it.id }) { library ->
                    LevelRow(library.name) { onLevel(KavitaLevel.Series(library)) }
                }

                is KavitaLevel.Series -> {
                    if (series.isEmpty()) {
                        item {
                            Text(
                                text = stringResource(R.string.kavita_empty),
                                style = MaterialTheme.typography.bodyMedium,
                                color = palette.textSecondary,
                            )
                        }
                    }
                    items(series, key = { it.id }) { each ->
                        LevelRow(each.name, fraction = each.fraction) {
                            onLevel(KavitaLevel.Chapters(each))
                        }
                    }
                }

                is KavitaLevel.Chapters -> volumes.forEach { volume ->
                    item(key = "volume-${volume.id}") {
                        // Loose chapters are not a volume, and labelling them as one would
                        // invent a "Volume 0" the server never had.
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
                        ChapterRow(chapter, isFetching = fetching == chapter.id) {
                            scope.launch {
                                fetching = chapter.id
                                openChapter(context, client, current.series.name, chapter)
                                    ?.let { (publication, path) -> onOpen(publication, path) }
                                fetching = null
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LevelRow(name: String, fraction: Double? = null, onOpen: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    // The progress bar carries no text, so a screen reader would read the name and stop.
    // Merged and spoken as one phrase, the way the library's own cells are.
    val percent = fraction?.takeIf { it > 0.0 }?.let { (it * 100).toInt() }
    val spoken = percent
        ?.let { "$name, " + stringResource(R.string.library_cell_progress, it) }
        ?: name
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs)
            .semantics(mergeDescendants = true) { contentDescription = spoken },
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyLarge, color = palette.textPrimary)
            if (fraction != null && fraction > 0.0) {
                LinearProgressIndicator(
                    progress = { fraction.toFloat() },
                    modifier = Modifier.fillMaxWidth(0.5f).padding(top = StoryArcSpace.hair),
                )
            }
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = palette.textTertiary,
        )
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
            isFetching -> CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.padding(2.dp))
            chapter.isFinished -> Icon(
                Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = palette.accent,
            )
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
private suspend fun openChapter(
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
