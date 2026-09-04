package app.storyarc.core.designsystem.control

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.ButtonGroupDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.ToggleButton
import androidx.compose.material3.ToggleButtonDefaults
import androidx.compose.material3.ToggleButtonShapes
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.text
import androidx.compose.ui.text.AnnotatedString

/**
 * One choice out of a small fixed set, drawn as Material's connected button group.
 *
 * **This replaces `SingleChoiceSegmentedButtonRow`, and nothing in the build asked it to.**
 * Material 3 Expressive says the baseline segmented button *"is no longer recommended"* and
 * names the connected button group as its replacement. Compose has not deprecated
 * `SegmentedButton`: `javap` over `material3-1.5.0-alpha26.aar` shows no `Deprecated`
 * annotation on it anywhere, so the compiler was silent about two call sites for as long as
 * they existed and would have stayed silent. `ConnectedButtonGroupTest` and the source guard
 * beside it are the only things that now notice.
 *
 * **There is no `ConnectedButtonGroup` in `material3` to call.** Verified against the same
 * artifact: no class or function in the library has "Connected" in its name. What the library
 * ships is one arrangement constant and three `@Composable` shape helpers keyed by position,
 * so the group is *assembled* — and the position arithmetic, which is the part that can be
 * wrong, is ours. That is the whole reason this is a shared component rather than a line
 * copied into each sheet.
 *
 * **Selection is the round-to-square shape change, and this component paints no fill.** That
 * is the distinction the Expressive guidance actually draws, and it arrives from Material's
 * own `checkedShape` — there is no `colors` argument anywhere below. Reproducing the retired
 * component's fill inside the new one would have been the change without the point.
 *
 * That is a claim about what this component *adds*, not about what a reader sees.
 * `ToggleButton`'s own default container colour still changes when checked, and in the
 * captures it reads louder at a glance than the shape does. The point is that the colour is
 * Material's current answer rather than the retired component's fill re-drawn by us — so it
 * moves when the library moves.
 *
 * **Accessibility is not what `ToggleButton` gives you.** `ToggleButton` announces
 * `role = Role.Checkbox` — read out of `ToggleButtonKt`'s bytecode, not from the
 * documentation — so a screen reader would call each option checked or unchecked and imply a
 * reader may pick any number of them. Exactly one of these is ever true, so each child is
 * given `Role.RadioButton` and a `selected` state, and the row is a `selectableGroup`: one
 * control with N selectable children rather than N unrelated buttons.
 *
 * Overriding the role is not enough on its own, and the note at the `clearAndSetSemantics`
 * call says what the merged node actually held before the semantics were cleared instead.
 *
 * **Where this is the wrong component.** Material specifies a connected group for two to
 * five *fixed* toggleable views. The library's search scope chips are neither fixed nor small
 * — a reader's configured sources are open and growing — and they stay `FilterChip`s for the
 * reason `quiet-shell-and-search` records. iOS keeps its segmented control, which is current
 * and idiomatic there; [ADR-0001] is why the two platforms may answer this differently.
 *
 * @param options the labels, in the order they are drawn. Two to five; one is handled but is
 *   not a group, and the shape says so.
 * @param selectedIndex which option is chosen. Out of range selects none, which is what a
 *   caller with no selection yet should pass rather than a sentinel of its own.
 * @param onSelect called with the position of the option chosen. **The position, not the
 *   option**, because the shapes are per-position: a caller that filters or reorders its
 *   options at run time has to be able to hand back an index into the list it just passed.
 */
@Composable
fun ConnectedButtonGroup(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        // One node for the group, so a screen reader reaches the children as alternatives to
        // each other rather than as a run of independent controls.
        modifier = modifier.selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(ButtonGroupDefaults.ConnectedSpaceBetween),
    ) {
        options.forEachIndexed { index, label ->
            val isSelected = index == selectedIndex
            ToggleButton(
                checked = isSelected,
                onCheckedChange = { onSelect(index) },
                // Recomputed from the list as it is now, never captured: a group whose
                // options are filtered or reordered between compositions has to be reshaped,
                // or its ends land in the middle.
                shapes = connectedButtonShapes(index, options.size),
                modifier = Modifier
                    // Equal thirds, which is what `SingleChoiceSegmentedButtonRow` gave its
                    // children for free and a plain `Row` does not.
                    .weight(1f)
                    // **`clearAndSetSemantics`, not `semantics`** — and the difference was
                    // measured rather than reasoned about. Adding `role` and `selected` on
                    // top of `ToggleButton` leaves its `ToggleableState` in place: the merged
                    // node came back
                    // `Role=RadioButton | Selected=true | ToggleableState=On`, so the option
                    // announced a radio button's role and a checkbox's state at once. Both
                    // derive from the same boolean, so they could never disagree — but the
                    // node this produces, role plus `selected` and nothing else, is exactly
                    // what `Modifier.selectable` builds, and that is the canonical
                    // single-select node rather than one with a spare property on it.
                    //
                    // The label is re-declared because clearing takes the descendant `Text`'s
                    // semantics with it, and `onClick` because it takes the button's. **Both
                    // are a maintenance trap worth naming**: an icon added beside the label
                    // here will be invisible to a screen reader unless it is named on this
                    // line too. What is deliberately not restored is autofill and
                    // text-substitution — a three-option view control is neither a form field
                    // nor translatable text — and semantic `RequestFocus`, which is an
                    // accessibility service's `ACTION_FOCUS`; keyboard and D-pad focus is
                    // `Modifier.focusable`'s behaviour and is untouched.
                    .clearAndSetSemantics {
                        role = Role.RadioButton
                        selected = isSelected
                        text = AnnotatedString(label)
                        onClick { onSelect(index); true }
                    },
            ) {
                // No `maxLines`, and deliberately: Material forbids a truncated label, and at
                // the largest accessibility text size a wrapped one is the only alternative
                // that keeps the word readable. The button grows; `design.md` rule 3 is that
                // the screen survives, not that the control keeps its height.
                Text(label)
            }
        }
    }
}

/**
 * Which of Material's three connected shapes a position takes, and the fourth case.
 *
 * The three helpers are `@Composable` because they resolve against `MaterialTheme.shapes`,
 * so this cannot be a plain function and its test cannot avoid a composition.
 *
 * **A group of one is not a leading button.** `connectedLeadingButtonShapes` is rounded on
 * its left and squared on its right, to join what follows it; a lone button squared off on
 * the side where nothing follows is a group with a missing member. Material's standalone
 * toggle-button shapes are the honest answer, spelled out from
 * [ToggleButtonDefaults]'s own three values rather than through its no-argument `shapes()`
 * overload, which is ambiguous with the three-defaulted-argument one beside it.
 */
@Composable
internal fun connectedButtonShapes(index: Int, count: Int): ToggleButtonShapes = when {
    count <= 1 -> ToggleButtonShapes(
        shape = ToggleButtonDefaults.shape,
        pressedShape = ToggleButtonDefaults.pressedShape,
        checkedShape = ToggleButtonDefaults.checkedShape,
    )
    index == 0 -> ButtonGroupDefaults.connectedLeadingButtonShapes()
    index == count - 1 -> ButtonGroupDefaults.connectedTrailingButtonShapes()
    else -> ButtonGroupDefaults.connectedMiddleButtonShapes()
}
