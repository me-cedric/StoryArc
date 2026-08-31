package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.cover.CoverlessWell
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/** How wide a cell on this shelf is. Narrower than the library's, because it is a sidebar of one series. */
private val SERIES_CELL_WIDTH = 108.dp

/** Enough pixels for a cell this size on the densest screen the app runs on. */
private const val SERIES_COVER_PIXELS = 400

/**
 * The rest of the series, as a shelf that behaves like every other shelf.
 *
 * `publication-detail` is explicit that this is not a second detail screen and not a series
 * screen: "*Other issues in this series* is a shelf on this screen". Each entry leads to its
 * own page — a cover is the detail verb everywhere in the app, and this shelf is covers.
 *
 * Absent rather than empty when the publication names no series or the library holds
 * nothing else in it, which is the same rule the continue-reading row follows.
 */
@Composable
internal fun DetailSeriesShelf(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (publications.isEmpty()) return
    val palette = LocalStoryArcPalette.current
    val finished = viewModel.finishedPublications()
    val kept = viewModel.keptOffline()

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.detail_series_heading),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.coverGap),
            contentPadding = PaddingValues(end = StoryArcSpace.sm),
        ) {
            items(publications, key = { it.id }) { publication ->
                DetailSeriesCell(
                    publication = publication,
                    viewModel = viewModel,
                    isFinished = publication.id in finished,
                    isOnDevice = publication.id in kept,
                    onOpen = onOpen,
                )
            }
        }
    }
}

/**
 * One entry, with its state said out loud.
 *
 * The design's accessibility note is the reason the label is built rather than left to the
 * title: "read, unread and on-this-device are marks on a cover for a sighted reader and
 * must be words in the label for everyone else". The mark under the cover carries the same
 * three answers, so nobody is reading a different shelf.
 */
@Composable
private fun DetailSeriesCell(
    publication: Publication,
    viewModel: LibraryViewModel,
    isFinished: Boolean,
    isOnDevice: Boolean,
    onOpen: (Publication) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, SERIES_COVER_PIXELS)
    }

    val fraction = viewModel.readFraction(publication)
    val state = when {
        isFinished -> stringResource(R.string.library_read_state_finished)
        fraction != null -> stringResource(R.string.library_read_state_in_progress)
        else -> stringResource(R.string.library_read_state_unread)
    }
    val onDevice = stringResource(R.string.catalogue_entry_downloaded)

    Column(
        modifier = Modifier
            .width(SERIES_CELL_WIDTH)
            .semantics {
                contentDescription = listOfNotNull(
                    publication.displayTitle,
                    publication.number?.takeIf { it.isNotBlank() }?.let { "#$it" },
                    state,
                    onDevice.takeIf { isOnDevice },
                ).joinToString(", ")
            },
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Surface(
            onClick = { onOpen(publication) },
            color = palette.surfaceSunken,
            // 4 dp, the printed-stock radius, the same as every other cover in the app.
            shape = RoundedCornerShape(StoryArcRadius.cover),
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
        ) {
            val art = cover
            if (art != null) {
                Image(
                    bitmap = art.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // The same well the library shelf draws, which this cell used to leave
                // empty. The caption below says `#3` or the title, and the title is the
                // longer answer — a run of unmarked volumes is exactly where a reader is
                // trying to tell one from another.
                //
                // No format, for the reason Home passes none: nothing on this shelf names
                // one. Its two caption lines are the volume and the read state, and a well
                // stands in for missing artwork rather than introducing a field the surface
                // around it does not carry.
                CoverlessWell(title = publication.displayTitle, format = null)
            }
        }
        Text(
            text = publication.number?.takeIf { it.isNotBlank() }?.let { "#$it" }
                ?: publication.displayTitle,
            style = MaterialTheme.typography.labelLarge,
            color = palette.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = if (isOnDevice) onDevice else state,
            style = MaterialTheme.typography.labelSmall,
            // The one fixed token on the page. `downloaded` has to survive a wallpaper, so
            // it comes from `Status` rather than from the scheme or from the cover.
            color = if (isOnDevice) StoryArcColor.Status.downloaded else palette.textTertiary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
