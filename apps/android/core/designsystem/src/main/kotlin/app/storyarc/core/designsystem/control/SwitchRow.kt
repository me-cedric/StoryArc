package app.storyarc.core.designsystem.control

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ListItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role

/**
 * One list row that is a switch.
 *
 * **The row is the toggleable, not the switch inside it.** A switch on its own is an unnamed
 * node — its label is a sibling, and a screen reader landing on it hears a bare on/off.
 * `toggleable` merges the label and the supporting line in, states the role, and widens the
 * target to the whole row, which `ListItem` lays out at 56 dp or more; `onCheckedChange = null`
 * on the switch is what stops the two from both claiming the gesture.
 *
 * @param supporting a second line saying what turning it on does, where the label alone does
 *   not. A switch's *value* is its on/off state, which the switch itself carries.
 */
@Composable
fun SwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    supporting: String? = null,
) {
    ListItem(
        supportingContent = supporting?.let { { Text(it) } },
        trailingContent = { Switch(checked = checked, onCheckedChange = null) },
        modifier = modifier
            .fillMaxWidth()
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange),
    ) { Text(label) }
}
