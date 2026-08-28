package app.storyarc.feature.library

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaSeries

/**
 * One series, as a cover.
 *
 * `kavita-server` asks for "cover, title, and progress" in a series list. A row of names
 * would satisfy the words and none of the point: a comic library is recognised by its
 * covers, and a reader scanning for one is looking at pictures.
 */
@Composable
fun KavitaSeriesCell(series: KavitaSeries, client: KavitaClient, onOpen: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    var cover by remember(series.id) { mutableStateOf<android.graphics.Bitmap?>(null) }

    // Through the client, not an image loader: Kavita's image routes want the reader's key,
    // and a loader has nowhere to put one.
    LaunchedEffect(series.id) {
        val bytes = runCatching { client.seriesCover(series.id) }.getOrNull()
            ?: return@LaunchedEffect
        cover = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
    }

    val read = series.fraction?.takeIf { it > 0.0 }
    val percent = read?.let { (it * 100).toInt() }
    val spoken = percent
        ?.let { "${series.name}, " + stringResource(R.string.library_cell_progress, it) }
        ?: series.name

    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier
            .clickable(onClick = onOpen)
            .semantics(mergeDescendants = true) { contentDescription = spoken },
    ) {
        Surface(
            color = palette.surfaceRaised,
            shape = RoundedCornerShape(StoryArcRadius.md),
            modifier = Modifier.fillMaxWidth().aspectRatio(2f / 3f),
        ) {
            val bitmap = cover
            if (bitmap != null) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(StoryArcRadius.md)),
                )
            } else {
                Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                    Text(
                        text = series.name,
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.textSecondary,
                        textAlign = TextAlign.Center,
                        maxLines = 4,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
                    )
                }
            }
        }
        Text(
            text = series.name,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        // Only when there is progress to show. A bar at zero says "started" about a series
        // nobody has opened.
        if (read != null) {
            LinearProgressIndicator(
                progress = { read.toFloat() },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
