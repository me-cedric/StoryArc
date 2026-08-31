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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.NaturalTheme
import app.storyarc.core.designsystem.theme.rememberNaturalTheme
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
 * Which of the two colour sources dresses the chrome, and what it is called.
 *
 * `native-experience`: the scheme "derives from the user's wallpaper by default, with a
 * setting to use the StoryArc palette instead". Always a note rather than sometimes one --
 * unlike [noteRes], which is null for the three appearances that are what their names say --
 * because this row has something to explain in both of its states.
 *
 * Under OLED Dark it explains an absence, for the same reason [noteRes] speaks up there:
 * true black and a wallpaper-derived wash are incompatible asks, and the explicit choice
 * wins. `StoryArcTheme` has always decided that -- the switch is inert there whatever it is
 * set to -- so the row says so rather than pretending to control something it does not.
 *
 * Natural is the second appearance that makes it inert, and for the same shape of reason:
 * a wallpaper-derived wash beside a clay accent is not a coherent theme, and `design.md`
 * asks Natural's accents to reach the whole app precisely so it is one.
 */
internal fun dynamicColourNoteRes(appearance: AppearanceMode, isNatural: Boolean = false): Int =
    when {
        appearance.isTrueBlack -> R.string.appearance_dynamic_colour_oled_note
        isNatural -> R.string.appearance_dynamic_colour_natural_note
        else -> R.string.appearance_dynamic_colour_note
    }

/**
 * The one-line reason the Natural switch cannot be combined with this appearance, or null
 * where it can.
 *
 * Non-null for OLED Dark alone -- see `NaturalTheme.isAvailable`.
 */
internal fun naturalUnavailableRes(appearance: AppearanceMode): Int? =
    if (NaturalTheme.isAvailable(appearance)) null else R.string.appearance_natural_unavailable

/**
 * Appearance, the colour source, and the one opt-in that ties the appearance to the
 * reading theme.
 *
 * The last two are separate by default and the spec says why: "a dark app chrome with a
 * paper-white page is a legitimate preference". That switch is the "single opt-in setting"
 * the same requirement then allows for readers who want them linked.
 */
@Composable
internal fun AppearanceGroup(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    modifier: Modifier = Modifier,
    /** The row a search result pointed at, if the reader arrived through one. */
    highlight: SettingsAnchor? = null,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
    // Natural is a second axis rather than a fifth appearance — see `NaturalTheme`. Its
    // own stored value, read from the same state the theme above reads, so flipping the
    // switch redresses the app without a restart.
    val natural = rememberNaturalTheme()

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        AppearanceMode.entries.forEach { mode ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectableRow(selected = settings.appearance == mode) {
                        onChange(settings.copy(appearance = mode))
                    }
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

        // Natural sits below the four rather than among them: it is a theme that crosses
        // them, so a fifth radio row would make it an alternative to dark mode — the
        // choice `settings-and-about` exists to avoid.
        val naturalUnavailable = naturalUnavailableRes(settings.appearance)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = natural.value,
                    enabled = naturalUnavailable == null,
                    role = Role.Switch,
                    onValueChange = { NaturalTheme.set(context, it) },
                )
                .padding(top = StoryArcSpace.md)
                .settingsHighlight(SettingsAnchor.NATURAL_THEME, highlight),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.appearance_natural),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(naturalUnavailable ?: R.string.appearance_natural_note),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
            Switch(
                checked = natural.value,
                onCheckedChange = null,
                enabled = naturalUnavailable == null,
            )
        }

        // `native-experience`'s opt-out. Disabled rather than hidden under OLED Dark: the
        // reader's answer is still stored and still shown, and a switch that silently did
        // nothing would be worse than one that says why it cannot. Natural makes it inert
        // for the same reason, so the same treatment applies.
        val isNatural = NaturalTheme.applies(natural.value, settings.appearance)
        val dynamicColourApplies = !settings.appearance.isTrueBlack && !isNatural
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = settings.useDynamicColor,
                    enabled = dynamicColourApplies,
                    role = Role.Switch,
                    onValueChange = { onChange(settings.copy(useDynamicColor = it)) },
                )
                .padding(top = StoryArcSpace.md)
                .settingsHighlight(SettingsAnchor.DYNAMIC_COLOUR, highlight),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.appearance_dynamic_colour),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(dynamicColourNoteRes(settings.appearance, isNatural)),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
            Switch(
                checked = settings.useDynamicColor,
                onCheckedChange = null,
                enabled = dynamicColourApplies,
            )
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
                .padding(top = StoryArcSpace.md)
                .settingsHighlight(SettingsAnchor.LINK_READING_THEME, highlight),
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
