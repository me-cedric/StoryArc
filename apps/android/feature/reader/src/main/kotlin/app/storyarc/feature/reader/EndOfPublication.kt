package app.storyarc.feature.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import app.storyarc.core.designsystem.control.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.CoverColours
import app.storyarc.core.model.Publication

/**
 * What the reader shows after the last page.
 *
 * `native-experience` puts a cover-derived accent and background tint "on a publication
 * detail screen or the reader". This screen is where the reader can honour that:
 * everywhere else in it the artwork is *on* screen, and the non-negotiable is that chrome
 * over a page never tints. Here the page is behind a near-opaque sheet, so the colour has
 * somewhere to go.
 *
 * `comic-reader`: "an end screen offers the next publication in the series or
 * reading list, marks this one finished". Marking is already done — the last page
 * records `isFinished` as it is turned to, because a reader who closes the app on
 * the last page has still finished it.
 *
 * Deleting the download is offered by the same scenario, and is here now (D7): an
 * action to remove it, or — when the automatic sweep would already do that — a
 * sentence saying so and an action to keep this one instead.
 */
@Composable
internal fun EndOfPublication(
    title: String,
    colours: CoverColours?,
    next: Publication?,
    onOpenNext: (Publication) -> Unit,
    onBack: () -> Unit,
    onClose: () -> Unit,
    /** `null` for a publication that was never a download. See [DownloadCleanupOffer]. */
    downloadCleanup: DownloadCleanupOffer? = null,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            // The wash, fading to black, and still near-opaque: the last page stays
            // faintly visible behind it, which is what says this screen is over the book
            // rather than after it.
            .background(
                brush = Brush.verticalGradient(
                    listOf(matteColour(colours?.wash), Color.Black),
                ),
                alpha = 0.92f,
            )
            .padding(StoryArcSpace.gutter),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg, Alignment.CenterVertically),
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            Text(
                text = stringResource(R.string.reader_end_finished),
                style = MaterialTheme.typography.titleLarge,
                color = Color.White,
            )
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
            )
        }

        if (next != null) {
            // The cover's accent, or the brand's. Never the raw extracted colour — what
            // `CoverColours` carries has already been adjusted to clear the floor, and
            // what is written on it was chosen for it rather than assumed to be white.
            Button(
                onClick = { onOpenNext(next) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = colours?.accent?.let { matteColour(it) }
                        ?: LocalStoryArcPalette.current.accent,
                    contentColor = colours?.onAccent?.let { matteColour(it) } ?: Color.White,
                ),
            ) {
                Text(stringResource(R.string.reader_end_next, next.displayTitle))
            }
        }

        DownloadCleanupRow(downloadCleanup)

        // Wrapping, not a Row: at a 2x font scale "Back to the last page" takes the
        // whole width and left the Library button a few dp wide.
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            // White, not the theme's accent: this overlay is near-black whatever
            // the app's appearance, and the accent on it fails contrast.
            val labels = ButtonDefaults.textButtonColors(contentColor = Color.White)
            TextButton(onClick = onBack, colors = labels) {
                Text(stringResource(R.string.reader_end_back))
            }
            TextButton(onClick = onClose, colors = labels) {
                Text(stringResource(R.string.reader_end_library))
            }
        }
    }
}
