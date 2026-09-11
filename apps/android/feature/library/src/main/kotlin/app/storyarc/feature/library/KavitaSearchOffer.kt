package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry

/**
 * The way across to a server's own search.
 *
 * **`kavita-server` requires the query to go to the server when the search is within a
 * Kavita source, and this is what the old scope selector was missing.** Narrowing the
 * library to a Kavita server and typing filtered the *local index* — what this device
 * happens to hold — and the server's own search, which reaches chapters, people, genres
 * and tags, was never asked.
 *
 * Offered rather than substituted: the local matches are useful and immediate, and a
 * search that silently left the device for the network would take a reader looking for a
 * downloaded chapter somewhere they did not ask to go.
 */
@Composable
internal fun KavitaSearchOffer(
    registry: SourceRegistry,
    query: LibraryQuery,
    onSearchOnServer: (Source, String) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val server = registry.sources.firstOrNull {
        it.id == query.scope.sourceId &&
            it.kind == SourceKind.KAVITA_SERVER &&
            query.search.isNotBlank()
    } ?: return

    Text(
        text = stringResource(R.string.library_search_on_server, server.displayName),
        style = MaterialTheme.typography.bodySmall,
        color = palette.accent,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSearchOnServer(server, query.search) }
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}
