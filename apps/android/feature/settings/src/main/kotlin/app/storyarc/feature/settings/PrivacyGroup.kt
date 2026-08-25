package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * The privacy posture, stated rather than toggled.
 *
 * `settings-and-about` asks for this to be "verifiable rather than merely stated", and
 * the reason there is nothing to switch here is the point: the app has no account, no
 * backend and no analytics, so there is nothing to opt out of. A screen full of disabled
 * toggles would imply the opposite.
 *
 * Clearing data and the diagnostic export are tasks 3.2 and 3.3, and both need something
 * that does not exist yet — a cache with a measurable size, and a log to redact.
 */
@Composable
internal fun PrivacyGroup(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        Text(
            text = stringResource(R.string.privacy_statement),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.privacy_sources),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
        Text(
            text = stringResource(R.string.privacy_pending),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )
    }
}
