package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.Publication

/**
 * The compact list.
 *
 * `library-browsing` requires a list beside the grid: past a certain size a library
 * is scanned by title rather than recognised by artwork, and a screen of covers
 * holds nine rows where a list holds twenty.
 *
 * iOS's `CoverList` shows the same four things in the same order.
 */
@Composable
internal fun CoverList(
    publications: List<Publication>,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    /**
     * What the reader has picked, or null when they are not picking.
     *
     * `collections-and-reading-lists` asks for bulk selection from the library, and the
     * library is whichever of these two layouts the reader chose. Selecting in one and not
     * the other would make the layout toggle a feature switch.
     */
    selection: Set<String>? = null,
    onToggle: (Publication) -> Unit = {},
    /** A long press, where a publication is put on a shelf. Null where nothing hosts it. */
    onAddToShelf: ((Publication) -> Unit)? = null,
    /**
     * Search results under their own headings. Empty means there is no search running and
     * the list is one run of rows.
     */
    groups: List<MatchGroup> = emptyList(),
    modifier: Modifier = Modifier,
) {
    val thumbnailWidth = 44.dp
    val density = LocalDensity.current
    val maxPixelSize = remember(density) { with(density) { thumbnailWidth.roundToPx() } }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(vertical = StoryArcSpace.sm),
    ) {
        // `library-browsing`: results are "grouped by match kind" while a search is running.
        // A list already reads as sections, so grouping here costs the reader nothing to
        // learn.
        val row: @Composable (Publication) -> Unit = { publication ->
            ListRow(
                publication,
                viewModel,
                onOpen,
                thumbnailWidth,
                maxPixelSize,
                isPicked = selection?.contains(publication.id),
                onToggle = onToggle,
                onAddToShelf = onAddToShelf,
            )
            HorizontalDivider()
        }
        if (groups.isEmpty()) {
            items(publications, key = { it.id }) { row(it) }
        } else {
            for (group in groups) {
                item(key = "heading-${group.kind}") {
                    MatchHeading(
                        group.kind,
                        modifier = Modifier.padding(horizontal = StoryArcSpace.gutter),
                    )
                }
                items(group.publications, key = { it.id }) { row(it) }
            }
        }
    }
}

@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun ListRow(
    publication: Publication,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    thumbnailWidth: androidx.compose.ui.unit.Dp,
    maxPixelSize: Int,
    /** Whether this one is picked, or null when the library is not in selection mode. */
    isPicked: Boolean? = null,
    onToggle: (Publication) -> Unit = {},
    onAddToShelf: ((Publication) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, maxPixelSize)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            // A publication that cannot be read is not tappable. Opening it only
            // to show the same refusal a second time wastes the user's tap.
            //
            // While the reader is picking, a tap picks -- even one that cannot be opened,
            // which can still be shelved and marked read. The long press is the same one
            // the grid answers: `native-experience` asks for the system's context gesture
            // wherever the app needs one, and a publication does not stop having
            // collections because the reader switched to the list layout. It is off while
            // picking, because the bar below is already offering the same actions for
            // everything that is picked.
            .combinedClickable(
                enabled = isPicked != null || publication.isOpenable,
                onClick = { if (isPicked != null) onToggle(publication) else onOpen(publication) },
                onLongClick = {
                    if (isPicked == null) onAddToShelf?.invoke(publication)
                },
            )
            .semantics { if (isPicked != null) selected = isPicked }
            // Material's 48 dp touch-target floor, per `native-experience`.
            .heightIn(min = StoryArcSpace.xxl + StoryArcSpace.lg)
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isPicked != null) PickMark(isPicked)

        Box(
            modifier = Modifier
                .width(thumbnailWidth)
                .aspectRatio(2f / 3f)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(StoryArcRadius.sm)),
            contentAlignment = Alignment.Center,
        ) {
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                // A tinted rectangle rather than nothing: a row whose thumbnail is
                // absent should still look like a row with a thumbnail, or the
                // list gains a ragged left edge wherever a cover is missing.
                Box(modifier = Modifier.fillMaxSize().background(palette.surfaceRaised))
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
        ) {
            Text(
                text = publication.displayTitle,
                style = MaterialTheme.typography.bodyLarge,
                color = palette.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = rowSubtitle(publication),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        viewModel.readFraction(publication)?.let { fraction ->
            // A number here rather than a bar: a list row is read, and "48%" is
            // quicker to read than a sliver of colour is to measure.
            Text(
                text = stringResource(R.string.library_cell_progress, (fraction * 100).toInt()),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textSecondary,
            )
        }
    }
}

/**
 * What distinguishes this row from its neighbours, format included: in a list the
 * artwork is too small to say what kind of publication this is.
 *
 * The source is last and only sometimes there. `library-browsing`: a publication "shows its
 * source only when more than one source is configured" — with one source the word would be
 * on every row and would separate nothing from nothing.
 */
@Composable
// No source here either. `library-browsing` says nothing on the shelf states which source
// a publication came from, and the list is the shelf drawn as rows — the grid losing the
// line while the list kept it would make the answer depend on a layout toggle. Origin has
// one home now: the provenance line on the publication's page.
private fun rowSubtitle(publication: Publication): String {
    val parts = buildList {
        if (!publication.isOpenable) add(stringResource(R.string.library_cell_cannot_open))
        val series = publication.series
        if (series != null && series != publication.displayTitle) {
            add(publication.number?.let { "$series #$it" } ?: series)
        } else {
            publication.authors.firstOrNull()?.let { add(it) }
        }
        add(publication.format.displayName)
    }
    return parts.joinToString(" · ")
}
