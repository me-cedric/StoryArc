package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaPublicationStatus
import app.storyarc.core.kavita.rating
import app.storyarc.core.kavita.status
import app.storyarc.core.model.KavitaCard
import app.storyarc.core.persistence.KavitaCardStore

/**
 * The two things a Kavita download says about itself that no file on this device can.
 *
 * `kavita-server`: "when a downloaded Kavita publication is opened with the server
 * unreachable, the cached server metadata is displayed, not the file's embedded metadata".
 * Five of the seven fields that requirement names -- a summary, genres, tags, people and a
 * release year -- reach the page through [KavitaCard.appliedTo], which lays the card over the
 * publication indexed from the file, because `Publication` has somewhere to put each of them.
 * The publication status and the age rating are the other two: there is no slot for either
 * and no local file states them, so they stay on the card and are read from it here.
 *
 * A named line each rather than a run of facts, which is the same decision `KavitaChapters`
 * made for the live answer and for the same reason: a rating dropped unlabelled into
 * "2020 · Ada Lovelace · Drama · Teen" is a rating a reader would take for a genre, and this
 * is the one field where being mistaken for something else matters.
 *
 * Absent for every publication that is not a kept Kavita chapter, which is most of them:
 * there is no card, so there is nothing to draw and no empty block left behind.
 *
 * iOS's `KavitaCardFacts` draws the same two lines from the same card.
 */
@Composable
fun KavitaCardFacts(publicationId: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val palette = LocalStoryArcPalette.current

    // Read once per publication rather than on every recomposition. The card is written when
    // the chapter is kept and never changes afterwards, so a redraw has nothing to learn.
    var card by remember(publicationId) { mutableStateOf<KavitaCard?>(null) }
    LaunchedEffect(publicationId) {
        card = KavitaCardStore.open(context).card(publicationId)
    }

    val held = card ?: return
    val status = held.status
    val rating = held.rating
    if (status == null && rating == null) return

    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        status?.let {
            Text(
                text = stringResource(R.string.kavita_status, stringResource(it.label)),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
        // Absent unless the server actually stated one. `KavitaCard.rating` drops Kavita's
        // `Unknown` and `Not Applicable`, because a line saying a book had been rated when
        // nobody rated it is worse than no line.
        rating?.let {
            Text(
                // The rating's own label, unchanged: ComicInfo.xml v2.1's vocabulary, which
                // is where Kavita takes it from. See the note beside `kavita_age_rating`.
                text = stringResource(R.string.kavita_age_rating, it.label),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
}

/** What this app calls each of Kavita's five states, in the reader's own language. */
internal val KavitaPublicationStatus.label: Int
    get() = when (this) {
        KavitaPublicationStatus.ONGOING -> R.string.kavita_status_ongoing
        KavitaPublicationStatus.HIATUS -> R.string.kavita_status_hiatus
        KavitaPublicationStatus.COMPLETED -> R.string.kavita_status_completed
        KavitaPublicationStatus.CANCELLED -> R.string.kavita_status_cancelled
        KavitaPublicationStatus.ENDED -> R.string.kavita_status_ended
    }
