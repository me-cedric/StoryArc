package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.AppearanceMode

/** How the four appearances are named on screen. */
internal val AppearanceMode.labelRes: Int
    get() = when (this) {
        AppearanceMode.SYSTEM -> R.string.appearance_system
        AppearanceMode.LIGHT -> R.string.appearance_light
        AppearanceMode.DARK -> R.string.appearance_dark
        AppearanceMode.OLED_DARK -> R.string.appearance_oled_dark
    }

/**
 * The one-line reason an appearance needs when it is not what its name implies.
 *
 * `settings-and-about`: OLED Dark is "honoured where it helps and explained where it does
 * not". Null for the three that need no explanation, because a note on all four is noise.
 */
internal val AppearanceMode.noteRes: Int?
    get() = if (this == AppearanceMode.OLED_DARK) R.string.appearance_oled_dark_note else null

/**
 * Appearance, and the one opt-in that ties it to the reading theme.
 *
 * The two are separate by default and the spec says why: "a dark app chrome with a
 * paper-white page is a legitimate preference". The switch is the "single opt-in setting"
 * the same requirement then allows for readers who want them linked.
 */
@Composable
internal fun AppearanceGroup(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        AppearanceMode.entries.forEach { mode ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = settings.appearance == mode,
                        role = Role.RadioButton,
                        onClick = { onChange(settings.copy(appearance = mode)) },
                    )
                    .semantics(mergeDescendants = true) {}
                    .padding(vertical = StoryArcSpace.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = settings.appearance == mode, onClick = null)
                Column(modifier = Modifier.padding(start = StoryArcSpace.sm)) {
                    Text(
                        text = stringResource(mode.labelRes),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                    )
                    mode.noteRes?.let {
                        Text(
                            text = stringResource(it),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textTertiary,
                        )
                    }
                }
            }
        }

        // The row is the toggleable, not the switch inside it. A switch on its own is
        // an unnamed node — its label is a sibling, and a screen reader landing on it
        // hears a bare on/off. `toggleable` merges the label in and widens the target.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = settings.linkReadingThemeToAppearance,
                    role = Role.Switch,
                    onValueChange = {
                        onChange(settings.copy(linkReadingThemeToAppearance = it))
                    },
                )
                .padding(top = StoryArcSpace.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.appearance_link_theme),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(R.string.appearance_link_theme_note),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
            Switch(
                checked = settings.linkReadingThemeToAppearance,
                onCheckedChange = null,
            )
        }
    }
}
