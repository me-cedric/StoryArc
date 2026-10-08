package app.storyarc.feature.library

import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.res.stringResource
import app.storyarc.core.catalogue.CoverCandidate
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.catalogue.candidates
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
import kotlinx.coroutines.launch

/**
 * Which ways of finding a cover the publication page offers.
 *
 * Task 6.2 of `cover-for-every-publication`. The two ways ask different questions of the
 * reader's privacy, and that is why this is one function and not two booleans read where they
 * are drawn:
 *
 * - **The title search** is this app asking three catalogues about the title, so it is offered
 *   only while the lookup switch is on.
 * - **The web search** is the reader's browser asking, with no request from this app at all,
 *   so it is offered whatever the switch says.
 *
 * iOS's `CoverFinderOffer` is its twin.
 */
internal data class CoverFinderOffer(val findACover: Boolean, val webSearch: Boolean) {
    internal companion object {
        fun of(lookUpIsOn: Boolean) = CoverFinderOffer(findACover = lookUpIsOn, webSearch = true)
    }
}

/** What the page's cover controls need to offer both ways, and what each way does. */
internal data class CoverFinder(
    val offer: CoverFinderOffer,
    /** The title the web search is for. */
    val title: String,
    val author: String?,
    /** Opens the candidate sheet. Called only where [CoverFinderOffer.findACover] holds. */
    val onFind: () -> Unit,
    /** Starts the browser. A composable holds no `Activity`, so the screen supplies this. */
    val onOpenWeb: (Intent) -> Unit,
)

/**
 * The reader's tap on a candidate, as a stored cover.
 *
 * The one place a looked-up picture becomes a chosen cover. The picture is fetched through
 * [client], which checks the setting and the host, and stored through [store], which is the
 * path the system picker already takes: [LibraryViewModel.setCover], so the crop to a cover's
 * shape, the override store and the redraw of every copy are one set of lines.
 *
 * Nothing calls this until the reader taps. `cover-art`: the app "never silently adopts a
 * match it is not certain of".
 *
 * @return whether the picture was stored. False is a picture that did not arrive or could not
 *   be used, and the page says so in the words it already uses for a picked picture.
 */
internal suspend fun adoptCandidate(
    candidate: CoverCandidate,
    client: CoverLookupClient,
    store: suspend (ByteArray) -> Boolean,
): Boolean {
    val picture = client.image(candidate.imageUrl) ?: return false
    return store(picture)
}

/** The three title catalogues' candidates for a publication, by its title and first author. */
internal suspend fun searchByTitle(
    client: CoverLookupClient,
    publication: Publication,
): List<CoverCandidate> =
    client.candidates(publication.displayTitle, publication.authors.firstOrNull())

/** The candidate sheet as a bottom sheet over the publication page. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CoverFinderSheet(
    publication: Publication,
    store: suspend (ByteArray) -> Boolean,
    onDone: (stored: Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        CoverFinderContent(publication = publication, store = store, onDone = onDone)
    }
}

/**
 * The search, its wait, and the candidates it finds.
 *
 * Apart from the sheet so a test can compose it without a window: [search] is what asks, and
 * [store] is what a tap on a row ends in.
 */
@Composable
internal fun CoverFinderContent(
    publication: Publication,
    store: suspend (ByteArray) -> Boolean,
    onDone: (stored: Boolean) -> Unit,
    modifier: Modifier = Modifier,
    client: CoverLookupClient = rememberCoverLookupClient(),
    search: suspend (CoverLookupClient, Publication) -> List<CoverCandidate> = ::searchByTitle,
) {
    val palette = LocalStoryArcPalette.current
    val scope = rememberCoroutineScope()
    var found by remember(publication.id) { mutableStateOf<List<CoverCandidate>?>(null) }
    LaunchedEffect(publication.id) { found = search(client, publication) }

    Column(
        modifier = modifier.fillMaxWidth().padding(horizontal = StoryArcSpace.gutter),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.covers_candidates),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        val candidates = found
        if (candidates == null) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                modifier = Modifier.fillMaxWidth().padding(vertical = StoryArcSpace.lg),
            ) {
                CircularProgressIndicator()
                Text(
                    text = stringResource(R.string.covers_finding),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                )
            }
        } else {
            CoverCandidateSheet(
                candidates = candidates,
                onChoose = { chosen ->
                    scope.launch { onDone(adoptCandidate(chosen, client, store)) }
                },
                client = client,
            )
        }
    }
}
