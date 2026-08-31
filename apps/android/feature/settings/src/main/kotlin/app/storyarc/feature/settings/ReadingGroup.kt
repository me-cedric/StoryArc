package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
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
    /** The row a search result pointed at, if the reader arrived through one. */
    highlight: SettingsAnchor? = null,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        // The note is off by default and said out loud, because `page-transitions` asks
        // for the volume buttons "where enabled in settings": volume keys that silently
        // stop changing the volume are a defect, not a feature.
        SettingsSwitchRow(
            title = stringResource(R.string.reading_volume_buttons),
            note = stringResource(R.string.reading_volume_buttons_note),
            checked = settings.turnPagesWithVolumeButtons,
            onChange = { onChange(settings.copy(turnPagesWithVolumeButtons = it)) },
            modifier = Modifier.settingsHighlight(SettingsAnchor.VOLUME_BUTTONS, highlight),
        )

        // The whole block, not its first row: the reading defaults are one setting to a
        // reader and several sections to the layout, and a tint that covered only the first
        // would point at "Books" rather than at the defaults.
        ReadingDefaults(
            store = readerStore,
            modifier = Modifier.settingsHighlight(SettingsAnchor.READING_DEFAULTS, highlight),
        )
    }
}
