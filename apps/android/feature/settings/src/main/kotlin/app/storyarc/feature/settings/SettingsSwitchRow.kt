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
import androidx.compose.ui.semantics.Role
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * A setting that is on or off: what it is, why, and the switch that says so.
 *
 * One composable rather than five copies. Every switch in Settings had been written out
 * again where it was needed -- three in [AppearanceGroup], one in [ReadingGroup], one
 * private helper in `DownloadsGroup` -- five identical `Row`s that had to agree about
 * three separate things and were only checked against each other by eye.
 *
 * **The row is the toggleable, not the switch inside it.** A `Switch` on its own is an
 * unnamed node: its label is a sibling, so a screen reader landing on it hears a bare
 * on/off. `toggleable` merges the label in and widens the target to the whole row, which is
 * why [Switch] below takes a null `onCheckedChange` -- a second clickable inside the first
 * would be a second announcement of the same setting.
 *
 * **[LABEL_GAP] is the fix for a defect, not decoration.** The label column takes the width
 * the switch leaves and nothing separated the two, so a description that happened to fill
 * its last line ran to the switch's outline: at the default text size the third Appearance
 * row put "a paper-white page" four pixels from the toggle, while the two above it cleared
 * theirs by fifteen -- the difference being where their text happened to break, not
 * anything either row did. `Arrangement.spacedBy` is measured *before* the weight, so the
 * gap is subtracted from the label's width rather than argued about afterwards, and no row
 * can lose it by wording.
 *
 * @param enabled whether the setting can be changed here at all. Disabled rather than
 *   hidden is a deliberate choice this app makes twice over in [AppearanceGroup]: the
 *   reader's stored answer is still shown, and [note] says why it cannot apply right now.
 *   A switch that silently did nothing would be worse than one that explains itself.
 */
@Composable
internal fun SettingsSwitchRow(
    title: String,
    note: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .toggleable(
                value = checked,
                enabled = enabled,
                role = Role.Switch,
                onValueChange = onChange,
            ),
        horizontalArrangement = Arrangement.spacedBy(LABEL_GAP),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            Text(
                text = note,
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
            )
        }
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

/**
 * What separates a setting's words from its switch.
 *
 * Material's own list item leaves this much between its supporting text and its trailing
 * control, and it is the smallest gap that still reads as one at a large font scale -- the
 * text grows into the space and the switch does not, so a gap chosen to look right at the
 * default size disappears at the largest.
 */
private val LABEL_GAP = StoryArcSpace.lg
