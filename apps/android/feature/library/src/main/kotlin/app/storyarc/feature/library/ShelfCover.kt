package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.model.CompositeCover
import app.storyarc.core.model.PublicationCollection

/**
 * A collection's own cover, drawn out of what it holds.
 *
 * `collections-and-reading-lists`: a collection's cover "is a composite of its first four
 * member covers unless the user sets a specific one". [CompositeCover] decides which four
 * and in what order -- the same decision iOS's `ShelfCover` asks for -- and this only draws
 * them.
 *
 * The artwork is the interface, so a shelf of collections is a shelf of covers rather than a
 * list of names with a folder glyph beside each one.
 */
@Composable
internal fun ShelfCover(
    collection: PublicationCollection,
    viewModel: LibraryViewModel,
    modifier: Modifier = Modifier,
    /** The width of the whole composite. Its height follows the 2:3 a cover has. */
    width: Dp = 44.dp,
) {
    val palette = LocalStoryArcPalette.current
    val density = LocalDensity.current
    val maxPixelSize = remember(density, width) { with(density) { width.roundToPx() } }

    val tiles = CompositeCover.tiles(collection)
    // Artwork that has arrived, keyed by the member it belongs to.
    val covers = remember(collection.id) { mutableStateMapOf<String, Bitmap>() }
    val publications by viewModel.publications.collectAsStateWithLifecycle()

    // Re-asked when the library grows, not only when the tiles change: a shelf opened while
    // the scan is still running has tiles whose publications are not there yet, and an effect
    // keyed on the tiles alone would never look a second time.
    LaunchedEffect(tiles, publications.size) {
        // Through [LibraryViewModel.cover], which decodes off the main thread and remembers
        // what it decoded. Ten collections on a shelf ask for forty covers, and forty
        // archives opened on the main thread is a screen that does not move.
        for (id in tiles) {
            if (covers.containsKey(id)) continue
            val publication = publications.firstOrNull { it.id == id } ?: continue
            viewModel.cover(publication, maxPixelSize)?.let { covers[id] = it }
        }
    }

    Surface(
        modifier = modifier
            .width(width)
            .aspectRatio(2f / 3f)
            // The row beside it says the collection's name and how much is in it. Spoken
            // here as well, the composite would announce four covers nobody asked to hear.
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
            // collection is empty still lines up with the ones below it.
            else -> Tile(null, Modifier.fillMaxSize())
        }
    }
}

@Composable
private fun Tile(bitmap: Bitmap?, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    if (bitmap == null) {
        androidx.compose.foundation.layout.Box(modifier.background(palette.surfaceRaised))
    } else {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = modifier,
        )
    }
}
