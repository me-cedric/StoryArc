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

        // On by default, unlike the row above, and for the opposite reason: tapping the
        // side of a page is how most readers turn one, where a volume key that stops
        // changing the volume is a surprise. The note says what the thirds are, because
        // "Tap zones" alone does not say what turning them off costs.
        SettingsSwitchRow(
            title = stringResource(R.string.reading_tap_zones),
            note = stringResource(R.string.reading_tap_zones_note),
            checked = settings.turnPagesByTappingTheEdges,
            onChange = { onChange(settings.copy(turnPagesByTappingTheEdges = it)) },
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
