package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
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
import app.storyarc.core.designsystem.grid.rememberCoverColumns
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaLibraryFolder
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.launch

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
    sourceId: String,
    store: KavitaProgressStore,
    /** Where a pulled position is written. See `KavitaSync.pull`. */
    progress: ProgressStore? = null,
    /** This server's own reading lists, which its chapters may be added to. */
    lists: List<ServerList> = emptyList(),
    level: KavitaLevel,
    onLevel: (KavitaLevel) -> Unit,
    /**
     * A term the reader typed in the library, which this server can answer itself.
     *
     * `kavita-server` asks a search within a Kavita source to reach the server; the library's
     * field filters the local index, and this is the question carried across.
     */
    searching: String = "",
    onOpen: (Publication, String) -> Unit,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current

    // Created once, from the address. Rebuilt on every redraw it would forget its session
    // token and re-authenticate for each request.
    val client = remember(address) { KavitaClient(address) }

    var libraries by remember(address) { mutableStateOf<List<KavitaLibraryFolder>>(emptyList()) }
    var series by remember(address) { mutableStateOf<List<KavitaSeries>>(emptyList()) }

    // A list that is empty and a list that has not arrived draw the same page, and the second
    // one lasts as long as the request does -- up to the twenty seconds `KavitaClient` allows.
    // A reader who has just added a server met a blank page with nothing to explain it, and a
    // reader who opened a library was told the library was empty while it was still being read.
    var askingLibraries by remember(address) { mutableStateOf(true) }
    var askingSeries by remember(address) { mutableStateOf(false) }

    // One search for the whole server rather than one per level: `kavita-server` asks for a
    // search of the *source*, not of whichever list happens to be on screen.
    val finder = remember(address) { KavitaFinder() }
    var isSearching by remember(address) { mutableStateOf(false) }
    var failure by remember(address) { mutableStateOf<String?>(null) }

    /** Why one library's series list is empty, when it is empty for a reason. */
    var seriesFailure by remember(address) { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    LaunchedEffect(client, searching) {
        // The question the reader already asked, put to the server that can answer it.
        if (searching.isNotEmpty() && finder.term.isEmpty()) {
            isSearching = true
            finder.type(searching)
            finder.run(context, client, sourceId)
        }
    }

    LaunchedEffect(client) {
        askingLibraries = true
        runCatching { client.libraries() }
            .onSuccess {
                libraries = it
                failure = null
                // Reaching the server is the "next successful connection" the spec retries on.
                KavitaSync.flush(store, sourceId, address)
            }
            // Said rather than swallowed. This used to fall back to an empty list, so a reader
            // whose key had been revoked saw a server with no libraries in it and nothing at
            // all to say why. `kavita-server` asks for an explanation, and this is it.
            .onFailure { failure = KavitaMessage.of(context, it, title) }
        askingLibraries = false
    }

    val current = level
    LaunchedEffect(current) {
        if (current is KavitaLevel.Series) {
            // Cleared rather than left standing: the previous library's series would otherwise
            // be the page for as long as this library takes to answer.
            series = emptyList()
            askingSeries = true
            // Said rather than swallowed, for the reason the library list above gives. This
            // used to fall back to an empty list, so a server too old to answer the listing
            // at all looked exactly like a library with nothing in it.
            runCatching { client.series(current.library.id) }
                .onSuccess {
                    series = it
                    seriesFailure = null
                }
                .onFailure {
                    series = emptyList()
                    seriesFailure = KavitaMessage.of(context, it, current.library.name)
                }
            askingSeries = false
        }
    }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = {
                    if (isSearching) {
                        KavitaSearchField(
                            finder = finder,
                            onSubmit = {
                                scope.launch { finder.run(context, client, sourceId) }
                            },
                        )
                    } else {
                        Text(
                            text = when (current) {
                                is KavitaLevel.Libraries -> title
                                is KavitaLevel.Series -> current.library.name
                                is KavitaLevel.Chapters -> current.series.name
                            },
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = {
                        isSearching = !isSearching
                        if (!isSearching) finder.clear()
                    }) {
                        Icon(
                            imageVector = if (isSearching) Icons.Filled.Close else Icons.Filled.Search,
                            contentDescription = stringResource(
                                if (isSearching) {
                                    R.string.kavita_search_close
                                } else {
                                    R.string.kavita_search_open
                                },
                            ),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
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
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
            )
        },
    ) { insets ->
        val body = Modifier.fillMaxSize().padding(insets)
        val edges = PaddingValues(StoryArcSpace.gutter)
        if (finder.isShowing) {
            KavitaHits(
                finder = finder,
                onOpenSeries = { id ->
                    scope.launch {
                        // Asked for by identity rather than built from the row. Kavita keys
                        // progress by library *and* series and a search result does not always
                        // carry the library, so a series built from the row alone would report
                        // reading against library zero for as long as the reader stayed in it.
                        runCatching { client.seriesDetail(id) }.getOrNull()?.let {
                            finder.clear()
                            isSearching = false
                            onLevel(KavitaLevel.Chapters(it))
                        }
                    }
                },
                onOpenKept = { publicationId ->
                    scope.launch {
                        openKeptPublication(context, publicationId)?.let { (publication, path) ->
                            onOpen(publication, path)
                        }
                    }
                },
                modifier = body,
                contentPadding = edges,
            )
            return@Scaffold
        }
        when (current) {
            is KavitaLevel.Libraries -> if (askingLibraries) {
                KavitaWaiting(body)
            } else LazyColumn(modifier = body, contentPadding = edges) {
                failure?.let { message ->
                    item(key = "failure") {
                        Text(
                            text = message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.textPrimary,
                            modifier = Modifier.padding(bottom = StoryArcSpace.md),
                        )
                    }
                }
                items(libraries, key = { it.id }) { library ->
                    LibraryRow(library.name) { onLevel(KavitaLevel.Series(library)) }
                }
            }

            is KavitaLevel.Series -> if (askingSeries) {
                KavitaWaiting(body)
            } else LazyVerticalGrid(
                columns = rememberCoverColumns(),
                contentPadding = edges,
                horizontalArrangement =
                    androidx.compose.foundation.layout.Arrangement.spacedBy(StoryArcSpace.md),
                verticalArrangement =
                    androidx.compose.foundation.layout.Arrangement.spacedBy(StoryArcSpace.md),
                modifier = body,
            ) {
                seriesFailure?.let { message ->
                    item(key = "seriesFailure", span = { GridItemSpan(maxLineSpan) }) {
                        Text(
                            text = message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.textPrimary,
                        )
                    }
                }
                if (seriesFailure == null && series.isEmpty()) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        Text(
                            text = stringResource(R.string.kavita_empty),
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.textSecondary,
                        )
                    }
                }
                items(series, key = { it.id }) { each ->
                    KavitaSeriesCell(each, client) { onLevel(KavitaLevel.Chapters(each)) }
                }
            }

            is KavitaLevel.Chapters -> KavitaChapters(
                series = current.series,
                client = client,
                sourceId = sourceId,
                store = store,
                progress = progress,
                lists = lists,
                onOpen = onOpen,
                modifier = body,
                contentPadding = edges,
            )
        }
    }
}

/**
 * Drawn while the server has been asked and has not answered.
 *
 * `kavita-server` asks that a reader is told why a page is empty. Silence for twenty seconds
 * is the one case where nothing was saying anything at all.
 */
@Composable
private fun KavitaWaiting(modifier: Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
private fun LibraryRow(name: String, onOpen: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs),
    ) {
        Text(
            text = name,
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
            modifier = Modifier.weight(1f),
        )
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = palette.textTertiary,
        )
    }
}
