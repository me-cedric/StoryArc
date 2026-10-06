package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.catalogue.CoverCandidate
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * The candidates a title search found, for the reader to choose from.
 *
 * `cover-art`: the app "SHALL show the candidates and let the reader choose", and "never
 * silently adopts a match it is not certain of, because a wrong cover is worse than none".
 * So this sheet has no "best match" and no automatic dismissal: it waits.
 *
 * An exact lookup by identifier never reaches this screen. A title is the uncertain case,
 * and this is what uncertainty looks like when it is shown rather than guessed at. iOS's
 * `CoverCandidateSheet` draws the same list.
 */
@Composable
internal fun CoverCandidateSheet(
    candidates: List<CoverCandidate>,
    onChoose: (CoverCandidate) -> Unit,
    modifier: Modifier = Modifier,
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
        items(candidates, key = { it.imageUrl }) { candidate ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onChoose(candidate) },
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            ) {
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
                    // Which catalogue answered, because a reader choosing between two nearly
                    // identical pictures has nothing else to choose on.
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
