package app.storyarc.feature.reader

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PageEntry
import app.storyarc.core.model.ReadingDirection

/**
 * The paged comic reader.
 *
 * `comic-reader` lists five transition modes. This is **slide**, the one that needs
 * no shader — page curl and continuous scroll belong to the
 * `reader-theming-and-page-transitions` change, whose Phase 0 spikes decide how the
 * curl is drawn on each platform. Building one here would pre-empt that decision.
 *
 * iOS's `ReaderView` is the same reader with `TabView` in place of `HorizontalPager`.
 */
@Composable
fun ReaderScreen(
    viewModel: ReaderViewModel,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pages by viewModel.pages.collectAsStateWithLifecycle()
    val failure by viewModel.failure.collectAsStateWithLifecycle()

    val configuration = LocalConfiguration.current
    val density = LocalDensity.current
    val maxPixelSize = with(density) {
        maxOf(configuration.screenWidthDp.dp, configuration.screenHeightDp.dp).roundToPx()
    }

    LaunchedEffect(Unit) { viewModel.open(maxPixelSize) }

    Box(
        // Black behind every page, whatever the app's appearance. A comic is read
        // against its own artwork, not against a themed surface.
        modifier = modifier.fillMaxSize().background(Color.Black),
        contentAlignment = Alignment.Center,
    ) {
        when {
            failure != null -> Message(failure!!)
            pages.isEmpty() -> CircularProgressIndicator(color = Color.White)
            else -> Pager(viewModel, pages)
        }

        // `comic-reader`: nothing is on screen while the user is reading. The close
        // control stays because the way out must never be hidden.
        IconButton(
            onClick = onClose,
            modifier = Modifier.align(Alignment.TopStart).padding(StoryArcSpace.md),
        ) {
            Surface(color = Color.White.copy(alpha = 0.2f), shape = CircleShape) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = stringResource(R.string.reader_close),
                    tint = Color.White,
                    modifier = Modifier.padding(StoryArcSpace.sm),
                )
            }
        }
    }
}

@Composable
private fun Pager(viewModel: ReaderViewModel, pages: List<PageEntry>) {
    val count = pages.size
    val isRightToLeft = viewModel.readingDirection == ReadingDirection.RIGHT_TO_LEFT

    /**
     * A display position turned back into the publication's own page number.
     *
     * Right-to-left reverses the *display* order and maps the index here, so the
     * model keeps counting pages the way the publication does and the indicator
     * says "2 of 4" rather than "3 of 4" for the same page. Mirroring the pager
     * with a transform instead would fight the paging gesture — iOS learned that
     * the hard way, and the note is in ReaderView.swift.
     */
    fun modelIndex(display: Int) = if (isRightToLeft) count - 1 - display else display
    fun displayIndex(model: Int) = if (isRightToLeft) count - 1 - model else model

    val pagerState = rememberPagerState(
        initialPage = displayIndex(viewModel.initialIndex),
        pageCount = { count },
    )

    // The pager owns its position and the model follows, in one direction only.
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.currentPage }.collect { page ->
            viewModel.warm(modelIndex(page))
        }
    }

    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
        val index = modelIndex(page)
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val bitmap = viewModel.image(index)
            when {
                bitmap != null -> Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = pages.getOrNull(index)?.path,
                    // Fit, not fill: cropping a comic page loses artwork, and
                    // comic-reader treats the whole page as the unit.
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize(),
                )
                // Said, not blank. publication-formats requires an archive to
                // report what it skipped, and this is where a skipped page is met.
                viewModel.isUnavailable(index) ->
                    Message(stringResource(R.string.reader_page_unavailable))

                else -> CircularProgressIndicator(color = Color.White)
            }
        }
    }

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Surface(
            color = Color.White.copy(alpha = 0.2f),
            shape = RoundedCornerShape(percent = 50),
            modifier = Modifier.padding(bottom = StoryArcSpace.lg),
        ) {
            Text(
                text = stringResource(
                    R.string.reader_page,
                    modelIndex(pagerState.currentPage) + 1,
                    count,
                ),
                style = MaterialTheme.typography.labelLarge,
                color = Color.White,
                modifier = Modifier.padding(
                    horizontal = StoryArcSpace.md,
                    vertical = StoryArcSpace.xs,
                ),
            )
        }
    }
}

@Composable
private fun Message(text: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier.padding(StoryArcSpace.gutter),
    ) {
        Icon(Icons.Filled.Warning, contentDescription = null, tint = Color.White.copy(alpha = 0.7f))
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = Color.White.copy(alpha = 0.7f),
            textAlign = TextAlign.Center,
        )
    }
}
