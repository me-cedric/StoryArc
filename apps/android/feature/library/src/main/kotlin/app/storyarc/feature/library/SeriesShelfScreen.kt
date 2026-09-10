package app.storyarc.feature.library

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * One series, and the publications inside it.
 *
 * `library-browsing`: "when a reader opens a series, then its publications are listed in
 * their own order, each openable, each carrying the marks a cover carries in the grid", and
 * "one gesture returns to the library, at the place the reader left it".
 *
 * The same grid the library draws, given one series' members: a cell here and a cell there
 * must be the same thing, because a reader who has learned what a cover means in the library
 * has learned it here too. That is also why this screen has no sections, no sort control and
 * no filter -- a series is already the answer to all three.
 *
 * The members are read from the library rather than passed in, so a series opened before a
 * source finished answering fills in as the rest arrives.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SeriesShelfScreen(
    name: String,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val publications by viewModel.publications.collectAsStateWithLifecycle()
    val members = publications.filter { it.series == name }

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
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
        if (members.isEmpty()) {
            // Not an error: a series whose source has not answered yet has no members to
            // list, and the library says elsewhere that the source is still being read.
            Text(
                text = stringResource(R.string.kavita_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
                modifier = Modifier.padding(insets).padding(StoryArcSpace.gutter),
            )
            return@Scaffold
        }
        CoverGrid(
            publications = members,
            viewModel = viewModel,
            onOpen = onOpen,
            modifier = Modifier.fillMaxSize().padding(insets),
        )
    }
}
