package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaLibraryFolder
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.Publication

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

    // Created once, from the address. Rebuilt on every redraw it would forget its session
    // token and re-authenticate for each request.
    val client = remember(address) { KavitaClient(address) }

    var libraries by remember(address) { mutableStateOf<List<KavitaLibraryFolder>>(emptyList()) }
    var series by remember(address) { mutableStateOf<List<KavitaSeries>>(emptyList()) }

    LaunchedEffect(client) {
        libraries = runCatching { client.libraries() }.getOrDefault(emptyList())
    }

    val current = level
    LaunchedEffect(current) {
        if (current is KavitaLevel.Series) {
            series = runCatching { client.series(current.library.id) }.getOrDefault(emptyList())
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
        val body = Modifier.fillMaxSize().padding(insets)
        val edges = PaddingValues(StoryArcSpace.gutter)
        when (current) {
            is KavitaLevel.Libraries -> LazyColumn(modifier = body, contentPadding = edges) {
                items(libraries, key = { it.id }) { library ->
                    LibraryRow(library.name) { onLevel(KavitaLevel.Series(library)) }
                }
            }

            is KavitaLevel.Series -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 140.dp),
                contentPadding = edges,
                horizontalArrangement =
                    androidx.compose.foundation.layout.Arrangement.spacedBy(StoryArcSpace.md),
                verticalArrangement =
                    androidx.compose.foundation.layout.Arrangement.spacedBy(StoryArcSpace.md),
                modifier = body,
            ) {
                if (series.isEmpty()) {
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
                onOpen = onOpen,
                modifier = body,
                contentPadding = edges,
            )
        }
    }
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
