package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcColor
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.CompositeCover
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.ReadingList

/**
 * A shelf's own cover, drawn out of what it holds.
 *
 * `collections-and-reading-lists`: a collection's cover "is a composite of its first four
 * member covers unless the user sets a specific one". [CompositeCover] decides which four
 * and in what order -- the same decision iOS's `ShelfCover` asks for -- and this only draws
 * them. [shelfTiles] extends the same rule to a reading list, where *first* means first in
 * the reader's order rather than first by identity.
 *
 * The artwork is the interface, so a shelf is a cover rather than a name with a folder glyph
 * beside it. It fills whatever it is given and keeps a cover's 2:3, so the caller decides how
 * big a shelf is and this decides only what goes on it.
 */
@Composable
internal fun ShelfCover(
    tiles: List<String>,
    viewModel: LibraryViewModel,
    modifier: Modifier = Modifier,
    /**
     * The widest this will ever be drawn. It sizes the decode and nothing else -- the frame
     * comes from the caller, and asking for pixels the screen will never show is how ten
     * shelves become ten full-size archive reads.
     */
    width: Dp = 180.dp,
) {
    val palette = LocalStoryArcPalette.current
    val density = LocalDensity.current
    val maxPixelSize = remember(density, width) { with(density) { width.roundToPx() } }

    // Artwork that has arrived, keyed by the member it belongs to.
    val covers = remember { mutableStateMapOf<String, Bitmap>() }
    val publications by viewModel.publications.collectAsStateWithLifecycle()

    // Re-asked when the library grows, not only when the tiles change: a shelf opened while
    // the scan is still running has tiles whose publications are not there yet, and an effect
    // keyed on the tiles alone would never look a second time.
    LaunchedEffect(tiles, publications.size) {
        // Through [LibraryViewModel.cover], which decodes off the main thread and remembers
        // what it decoded. Ten shelves ask for forty covers, and forty archives opened on the
        // main thread is a screen that does not move.
        for (id in tiles) {
            if (covers.containsKey(id)) continue
            val publication = publications.firstOrNull { it.id == id } ?: continue
            viewModel.cover(publication, maxPixelSize)?.let { covers[id] = it }
        }
    }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(2f / 3f)
            // The caption under it says the shelf's name and how much is in it. Spoken here
            // as well, the composite would announce four covers nobody asked to hear.
            .clearAndSetSemantics {},
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.sm),
        border = BorderStroke(1.dp, palette.borderSubtle),
    ) {
        when {
            tiles.size >= CompositeCover.TILE_COUNT -> Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    Tile(covers[tiles[0]], Modifier.weight(1f).fillMaxSize())
                    Tile(covers[tiles[1]], Modifier.weight(1f).fillMaxSize())
                }
                Row(Modifier.fillMaxWidth().weight(1f)) {
                    Tile(covers[tiles[2]], Modifier.weight(1f).fillMaxSize())
                    Tile(covers[tiles[3]], Modifier.weight(1f).fillMaxSize())
                }
            }

            tiles.isNotEmpty() -> Tile(covers[tiles.first()], Modifier.fillMaxSize())

            // Nothing in it yet. A blank in the shape of a cover, so a shelf whose first
            // collection is empty still lines up with the ones beside it.
            else -> Tile(null, Modifier.fillMaxSize())
        }
    }
}

/**
 * The four covers a reading list stands behind, in the reader's own order.
 *
 * [CompositeCover] orders a collection's tiles by identity because a collection is a set and
 * a set has no first. A reading list is the opposite case -- its order *is* its meaning -- so
 * its first four entries are its first four tiles, and a list the reader reorders redraws
 * itself. Everything else is [CompositeCover]'s rule kept word for word: four tiles or one,
 * never a quadrant with a hole in it.
 */
internal fun shelfTiles(list: ReadingList): List<String> =
    if (list.entries.size >= CompositeCover.TILE_COUNT) {
        list.entries.take(CompositeCover.TILE_COUNT)
    } else {
        list.entries.take(1)
    }

/** The tiles a collection stands behind. Named to sit beside its reading-list twin. */
internal fun shelfTiles(collection: PublicationCollection): List<String> =
    CompositeCover.tiles(collection)

/**
 * A shelf as the reader meets it on the Shelves screen: its artwork, then its name.
 *
 * §3.6 of the revamp: "a collection with no artwork is a folder listing". So a shelf is drawn
 * the way a publication is drawn -- cover first, caption under it, never over it -- and the
 * two read as the same kind of thing, which is the point: a shelf is something you open, not
 * a row you tick.
 *
 * iOS's `ShelfCard` is the same card. Deleting is a long press rather than a bin icon on
 * every card: a grid of covers with a control stapled to each one is a file manager again,
 * and [combinedClickable]'s long-press label is what a screen reader offers instead.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ShelfCard(
    viewModel: LibraryViewModel,
    title: String,
    /** Where it came from and how much is in it, already joined. */
    subtitle: String,
    /** The member identities behind the composite. Empty draws the blank shelf. */
    tiles: List<String>,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * How far through an ordered shelf the reader is, nought to one. Null for a collection,
     * which has no order and therefore no position in one.
     */
    progress: Float? = null,
    /** How many edits this shelf still owes its online library. */
    pending: Int = 0,
    /** Null for a shelf this device does not own, where deleting is the library's business. */
    onDelete: (() -> Unit)? = null,
) {
    val palette = LocalStoryArcPalette.current
    var menuOpen by remember { mutableStateOf(false) }
    val deleteLabel = stringResource(R.string.shelves_delete, title)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = onOpen,
                onLongClick = if (onDelete == null) null else { { menuOpen = true } },
                onLongClickLabel = deleteLabel,
            ),
    ) {
        Box {
            ShelfCover(tiles = tiles, viewModel = viewModel)

            // `design.md` on a cover cell: "progress as a thin rail across the bottom edge,
            // never a ring over the art". A reading list has one for the same reason a
            // publication does -- it is a thing you are partway through.
            if (progress != null && progress > 0f) {
                Box(Modifier.fillMaxSize().wrapContentHeight(Alignment.Bottom)) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(RAIL_HEIGHT)
                            .background(Color.Black.copy(alpha = 0.35f)),
                    )
                    Box(
                        Modifier
                            .fillMaxWidth(progress.coerceIn(0f, 1f))
                            .height(RAIL_HEIGHT)
                            .background(
                                if (progress >= 1f) palette.textSecondary else palette.accent,
                            ),
                    )
                }
            }

            if (onDelete != null) {
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(deleteLabel) },
                        onClick = {
                            menuOpen = false
                            onDelete()
                        },
                    )
                }
            }
        }

        Column(modifier = Modifier.padding(top = StoryArcSpace.sm)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = palette.textTertiary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            // `collections-and-reading-lists`: "the pending state is visible on the list". On
            // the shelf as well as inside it, because a reader looking for what has not gone
            // out yet should not have to open every list to find it.
            if (pending > 0) {
                Text(
                    text = pluralStringResource(R.plurals.shelves_pending, pending, pending),
                    style = MaterialTheme.typography.bodySmall,
                    color = StoryArcColor.Status.offline,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

/** The rail across a shelf's foot, the same three points a cover cell's rail is. */
private val RAIL_HEIGHT = 3.dp

@Composable
private fun Tile(bitmap: Bitmap?, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    if (bitmap == null) {
        Box(modifier.background(palette.surfaceRaised))
    } else {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = modifier,
        )
    }
}
