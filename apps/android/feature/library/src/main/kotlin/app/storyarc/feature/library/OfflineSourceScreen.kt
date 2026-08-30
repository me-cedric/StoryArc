package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * What a server, catalogue or share shows while it is not answering.
 *
 * **This is the honest half of `sources`' "cached contents remain browsable".** That clause
 * holds for a local folder, whose catalogue is written to disk by `LibraryCache` and restored
 * before the next walk starts. It does not hold — and deliberately does not — for an OPDS
 * catalogue, a Kavita server or an SMB share: their responses are never written to disk, so
 * there is nothing to browse when the server stops answering.
 *
 * Two answers were possible and one had to be chosen. Caching enough of the last good
 * response to browse it means a second catalogue store per source type — feed pages, series
 * lists, chapter lists and their covers — living in a cache directory the system may evict
 * mid-browse, so this screen would still have to exist for the evicted case. It also puts
 * server-supplied URLs on disk, which is the one place an acquisition link's embedded
 * credential could survive a launch. So the app says plainly what is true instead, and the
 * spec scenario was amended to match rather than left describing something no code does.
 *
 * What a reader keeps is what they downloaded: those publications are in the library and stay
 * readable, which is what this says rather than leaving them to find out. iOS's
 * `OfflineSource` says the same three sentences.
 */
@Composable
fun OfflineSourceScreen(
    name: String,
    /**
     * Asks the source again, now. `sources` retries on its own with backoff; this is for a
     * reader who has just walked back into Wi-Fi range and would rather not wait for it.
     */
    onRetry: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(name) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.catalogue_back),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = stringResource(R.string.source_offline_title),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            Text(
                text = stringResource(R.string.source_offline_body, name),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
            Button(onClick = onRetry) {
                Text(stringResource(R.string.source_offline_retry))
            }
        }
    }
}
