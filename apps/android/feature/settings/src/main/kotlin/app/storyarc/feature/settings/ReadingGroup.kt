package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings
import app.storyarc.core.persistence.ReaderPreferences

/**
 * Reading, which holds less than its name suggests.
 *
 * Two things: the one reading preference that is neither typographic nor per-series, and
 * the *defaults* a series never opened before is read with. The defaults live in
 * `ShelfMemory` rather than in `AppSettings`, because that store is what makes "changing a
 * default does not overwrite a per-series choice" true by construction.
 */
@Composable
internal fun ReadingGroup(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    readerStore: ReaderPreferences,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        // The row is the toggleable, not the switch inside it — the same reason as the
        // appearance link: a switch whose label is a sibling is a nameless on/off to a
        // screen reader.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = settings.turnPagesWithVolumeButtons,
                    role = Role.Switch,
                    onValueChange = {
                        onChange(settings.copy(turnPagesWithVolumeButtons = it))
                    },
                ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.reading_volume_buttons),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                // Off by default and said out loud, because `page-transitions` asks for
                // the volume buttons "where enabled in settings": volume keys that
                // silently stop changing the volume are a defect, not a feature.
                Text(
                    text = stringResource(R.string.reading_volume_buttons_note),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
            Switch(
                checked = settings.turnPagesWithVolumeButtons,
                onCheckedChange = null,
            )
        }

        ReadingDefaults(store = readerStore)
    }
}
