package app.storyarc.feature.library

import android.text.format.DateUtils
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * States that the shelf on screen is last session's, and when it was confirmed.
 *
 * `sources` asks for "a single unobtrusive indicator" saying "that content is cached and
 * when it was last refreshed". One line, in the secondary text colour, that leaves as soon
 * as a walk finishes — at which point the shelf is not cached, it is current, and a notice
 * still claiming otherwise would be the indicator lying quietly in the corner.
 *
 * Not an error and not a warning. Offline is a normal state; so is a library that has not
 * been rewalked yet. iOS shows the same line above its grid, from `CachedNotice`.
 */
@Composable
internal fun CachedNotice(refreshedAtEpochMillis: Long) {
    val palette = LocalStoryArcPalette.current
    // The platform's own phrasing for "twelve minutes ago", which `localization` requires
    // rather than a string this app assembles and then has to translate four times.
    val relative = DateUtils.getRelativeTimeSpanString(
        refreshedAtEpochMillis,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
    ).toString()

    Text(
        text = stringResource(R.string.library_cached, relative),
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}
