package app.storyarc

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
import app.storyarc.feature.library.LibraryViewModel

/** The widest a cover is drawn on the home surface, and the pixels it is decoded at. */
private val COVER_WIDTH = 128.dp
private const val COVER_PIXELS = 512

/**
 * The reading room — the surface the app opens on.
 *
 * A first cut: it leads with what the reader is part-way through, which `home-screen`
 * requires of it and which is the only shelf that can be built from local data alone, so it
 * is the same surface whether every server is up or every one of them is down. Up next,
 * Recently added and the pinned shelves are the home slice's, not the shell's; what this
 * settles is that Home *is* a destination and that the app lands on it.
 */
@Composable
internal fun HomeDestination(host: AppHost) {
    val palette = LocalStoryArcPalette.current
    val continueReading by host.library.continueReading.collectAsStateWithLifecycle()
    val open: (Publication) -> Unit = { publication ->
        host.library.location(publication)?.let { host.open(publication, it) }
    }

    DestinationScaffold(title = stringResource(R.string.app_name)) {
        if (continueReading.isEmpty()) {
            // `home-screen`: with nothing part-way through, Keep reading is absent rather
            // than shown empty. What is left is one sentence and the way out of it.
            item {
                EmptyDestination(
                    sentence = stringResource(R.string.home_empty),
                    onOpenLibrary = { host.goToLibrary() },
                )
            }
        } else {
            item {
                Text(
                    text = stringResource(R.string.home_keep_reading),
                    style = MaterialTheme.typography.titleLarge,
                    color = palette.textPrimary,
                    modifier = Modifier.padding(horizontal = StoryArcSpace.gutter),
                )
            }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.coverGap),
                    modifier = Modifier.fillMaxWidth().padding(top = StoryArcSpace.md),
                ) {
                    items(continueReading, key = { it.id }) { publication ->
                        CoverCell(
                            publication = publication,
                            viewModel = host.library,
                            onOpen = { open(publication) },
                        )
                    }
                }
            }
        }
    }
}

/**
 * One cover, letterboxed rather than cropped.
 *
 * `design.md` is explicit that artwork is never cropped to fill a cell: a comic cover is
 * the thing the reader recognises the book by, and the letterbox goes onto `surfaceSunken`
 * so the cell still reads as a cell. The radius is the cover radius token, 4 dp, not the
 * card radius — the same correction the cover grid carries.
 */
@Composable
private fun CoverCell(
    publication: Publication,
    viewModel: LibraryViewModel,
    onOpen: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(publication.id) { cover = viewModel.cover(publication, COVER_PIXELS) }

    Column(
        modifier = Modifier.width(COVER_WIDTH).clickable(onClick = onOpen),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(COVER_ASPECT)
                .clip(RoundedCornerShape(StoryArcRadius.cover))
                .background(palette.surfaceSunken),
            contentAlignment = Alignment.Center,
        ) {
            cover?.let {
                Image(
                    bitmap = it.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Text(
            text = publication.displayTitle,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** The proportions of a comic cover, near enough for every publisher. */
private const val COVER_ASPECT = 2f / 3f
