package app.storyarc.feature.library

import android.app.Application
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.catalogue.CoverCandidate
import app.storyarc.core.catalogue.CoverLookupClient
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PageDecoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Marks a candidate's picture once it is drawn, so a test can count what the reader sees. */
internal const val CANDIDATE_PICTURE_TAG = "cover-candidate-picture"

private val PICTURE_WIDTH = 44.dp
private const val PICTURE_PIXELS = 264

/**
 * The key a candidate's row is filed under.
 *
 * Provider, address and position, because two catalogues can answer one title with the same
 * picture and one catalogue can repeat itself, and a lazy list that meets a key twice throws.
 * The position makes the key unique by construction, which no field of the answer can.
 */
internal fun candidateKey(index: Int, candidate: CoverCandidate): String =
    "${candidate.provider.name}|${candidate.imageUrl}|$index"

/**
 * The candidates a title search found, each with its picture, for the reader to choose from.
 *
 * `cover-art`: the app "SHALL show the candidates and let the reader choose". A reader choosing
 * between nearly identical titles chooses on the picture, so each row draws it. Every picture
 * is fetched through [CoverLookupClient.image], the one path that checks the host and the
 * setting: a picture from an address the setting does not name is never requested and its row
 * draws no picture. iOS's `CoverCandidateSheet` is its twin.
 */
@Composable
internal fun CoverCandidateSheet(
    candidates: List<CoverCandidate>,
    onChoose: (CoverCandidate) -> Unit,
    modifier: Modifier = Modifier,
    client: CoverLookupClient = rememberCoverLookupClient(),
) {
    val palette = LocalStoryArcPalette.current
    if (candidates.isEmpty()) {
        Text(
            text = stringResource(R.string.covers_candidates_none),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
            modifier = modifier,
        )
        return
    }

    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        itemsIndexed(candidates, key = ::candidateKey) { _, candidate ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onChoose(candidate) },
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            ) {
                CandidatePicture(candidate, client)
                Column {
                    Text(
                        text = candidate.title,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                    )
                    candidate.subtitle?.let {
                        Text(
                            text = it,
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textSecondary,
                        )
                    }
                    Text(
                        text = stringResource(
                            R.string.covers_candidates_from,
                            candidate.provider.displayName,
                        ),
                        style = MaterialTheme.typography.labelSmall,
                        color = palette.textTertiary,
                    )
                }
            }
        }
        item {
            Text(
                text = stringResource(R.string.covers_candidates_note),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textSecondary,
            )
        }
    }
}

/**
 * One candidate's picture, or the space it will take.
 *
 * Decorative: the title beside it says what this is, and a description here would read the
 * same title twice. The space is held while the picture loads and when none comes, so the rows
 * do not shift as the answers arrive.
 */
@Composable
private fun CandidatePicture(candidate: CoverCandidate, client: CoverLookupClient) {
    val picture by produceState<ImageBitmap?>(null, candidate.imageUrl, client) {
        value = withContext(Dispatchers.IO) {
            client.image(candidate.imageUrl)
                ?.let { runCatching { PageDecoder.decode(it, PICTURE_PIXELS) }.getOrNull() }
        }?.asImageBitmap()
    }
    Box(Modifier.width(PICTURE_WIDTH).aspectRatio(2f / 3f)) {
        picture?.let {
            Image(
                bitmap = it,
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier.testTag(CANDIDATE_PICTURE_TAG),
            )
        }
    }
}

/** The process's one lookup client, so a sheet asks through the same gate and cache as the shelf. */
@Composable
private fun rememberCoverLookupClient(): CoverLookupClient =
    CoverLookup.client(LocalContext.current.applicationContext as Application)
