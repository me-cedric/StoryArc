package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * The scan's own count and a way to stop it, drawn in the shelf's notice strip once the
 * shelf already has rows on it.
 *
 * [Scanning] draws the same count, centred, but only while the shelf is still empty --
 * `LibraryScreen`'s own `when` never reached that branch once there was anything to show. So
 * a rescan, or a second folder added to a library that already had books, reported no count
 * of items found and offered no action to stop it. 10.6, 10.7.
 */
@Composable
internal fun ScanProgressNotice(found: Int, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = pluralStringResource(R.plurals.library_scanning, found, found),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onCancel) { Text(stringResource(R.string.library_scan_cancel)) }
    }
}
