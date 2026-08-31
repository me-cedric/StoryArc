package app.storyarc.feature.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import app.storyarc.core.model.PageFit
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.scrollAxis

/*
 * How this publication behaves, as menu rows rather than as a strip of icons.
 *
 * **What changed here.** Every control in this file was an icon on a floating toolbar over
 * the page: a book glyph for the transition, a fullscreen glyph for the fit, a swap glyph
 * for the direction, a padlock for the rotation, a column glyph for the spread offset.
 * Six pictures a reader had to recognise, three of which carried their *state* only in the
 * picture — a tinted `ViewColumn` against an untinted one is not a sentence.
 *
 * `comic-reader` moved them behind one menu, "named in words rather than by icon alone", so
 * each is a row now: its own name on the left, its own current value on the right. That is
 * the same argument `reading-themes` makes about a slider — "a reader cannot report, repeat
 * or reason about a position". A row reading *Reading direction — Right to left* is a fact;
 * an arrow glyph is a guess.
 *
 * The naming extensions at the foot of the file are unchanged: the enums live in
 * `:core:model` and carry no resources, because the domain has no business holding UI copy.
 */

/**
 * The settings section of the reader's menu.
 *
 * In the order a reader asks about them: how the page turns, how it is sized, which way it
 * runs, and then the two switches.
 */
@Composable
internal fun ReaderSettingsRows(
    choices: TransitionChoices,
    showsSeparator: Boolean,
    onToggleSeparator: (Boolean) -> Unit,
    onChooseTransition: (PageTransition) -> Unit,
    fit: PageFit,
    onChooseFit: (PageFit) -> Unit,
    direction: ReadingDirection,
    onChooseDirection: (ReadingDirection) -> Unit,
    hasPairs: Boolean,
    isOffset: Boolean,
    onToggleOffset: (Boolean) -> Unit,
    isOrientationLocked: Boolean,
    onToggleOrientation: (Boolean) -> Unit,
) {
    TransitionRow(
        choices = choices,
        onChoose = onChooseTransition,
        showsSeparator = showsSeparator,
        onToggleSeparator = onToggleSeparator,
    )
    FitRow(fit = fit, onChange = onChooseFit)
    DirectionRow(direction = direction, onChoose = onChooseDirection)

    // Only where there is a pairing to shift. `comic-reader` offers the offset "for
    // publications whose cover throws the pairing off", which is a question that does not
    // arise in portrait or in a scroll.
    if (hasPairs) {
        SwitchRow(
            label = stringResource(R.string.reader_spreads_offset),
            checked = isOffset,
            onCheckedChange = onToggleOffset,
        )
    }

    // `comic-reader` scopes the lock to the reader, so it is here rather than in Settings.
    // A switch rather than the padlock it replaces: the padlock's two glyphs were the only
    // statement of which state it was in.
    SwitchRow(
        label = stringResource(R.string.reader_orientation_lock),
        checked = isOrientationLocked,
        onCheckedChange = onToggleOrientation,
    )
}

/**
 * The page-transition row.
 *
 * `page-transitions` is specific about what a mode that cannot run looks like: "shown
 * unavailable with a one-line reason, never silently absent". So a row disabled by reduced
 * motion stays, greyed, with the reason under it — a control that vanishes teaches nothing.
 *
 * Curl is the one exception, and the spec draws that line itself: where the *device* cannot
 * honour it, Curl is "absent from the picker on that device… with the reason stated once in
 * plain language — naming the requirement, not an API level".
 */
@Composable
private fun TransitionRow(
    choices: TransitionChoices,
    onChoose: (PageTransition) -> Unit,
    showsSeparator: Boolean,
    onToggleSeparator: (Boolean) -> Unit,
) {
    ChoiceRow(
        label = stringResource(R.string.reader_transition),
        value = stringResource(choices.effective.labelRes),
    ) { dismiss ->
        choices.offered.forEach { mode ->
            val reason = choices.unavailable[mode]
            DropdownMenuItem(
                text = {
                    Column {
                        Text(stringResource(mode.labelRes))
                        if (reason != null) {
                            Text(
                                text = stringResource(reason.labelRes),
                                style = MaterialTheme.typography.labelSmall,
                            )
                        }
                    }
                },
                leadingIcon = {
                    RadioButton(
                        selected = choices.chosen == mode,
                        onClick = null,
                        enabled = reason == null,
                    )
                },
                enabled = reason == null,
                onClick = {
                    onChoose(mode)
                    dismiss()
                },
            )
        }
        // Only where there are stitched pages to separate. In a paged mode there is a whole
        // screen between one page and the next already.
        if (choices.effective.scrollAxis != null) {
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.reader_separator)) },
                leadingIcon = { Checkbox(checked = showsSeparator, onCheckedChange = null) },
                onClick = { onToggleSeparator(!showsSeparator) },
            )
        }
        if (choices.curlIsAbsent) {
            // Once, and in the reader's language rather than the platform's.
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.reader_transition_no_curl),
                        style = MaterialTheme.typography.labelSmall,
                    )
                },
                enabled = false,
                onClick = {},
            )
        }
    }
}

/** How the page is sized. `comic-reader` names the four modes. */
@Composable
private fun FitRow(fit: PageFit, onChange: (PageFit) -> Unit) {
    ChoiceRow(
        label = stringResource(R.string.reader_fit),
        value = stringResource(fit.labelRes),
    ) { dismiss ->
        PageFit.entries.forEach { candidate ->
            DropdownMenuItem(
                text = { Text(stringResource(candidate.labelRes)) },
                leadingIcon = { RadioButton(selected = fit == candidate, onClick = null) },
                onClick = {
                    onChange(candidate)
                    dismiss()
                },
            )
        }
    }
}

/**
 * Which way the pages run.
 *
 * `comic-reader` opens a publication in the direction its metadata declares and lets the
 * reader overrule that, for the series. The row states the current direction, which matters
 * more here than anywhere else in this menu: metadata gets it wrong often enough that a
 * reader who suspects it needs to see which way the comic is running, not only be able to
 * flip it.
 */
@Composable
private fun DirectionRow(direction: ReadingDirection, onChoose: (ReadingDirection) -> Unit) {
    ChoiceRow(
        label = stringResource(R.string.reader_direction),
        value = stringResource(direction.labelRes),
    ) { dismiss ->
        ReadingDirection.entries.forEach { candidate ->
            DropdownMenuItem(
                text = { Text(stringResource(candidate.labelRes)) },
                leadingIcon = { RadioButton(selected = direction == candidate, onClick = null) },
                onClick = {
                    onChoose(candidate)
                    dismiss()
                },
            )
        }
    }
}

/**
 * One row that names an axis, states its value, and opens the choices.
 *
 * The whole row is the target rather than a trailing glyph: `native-experience` asks for the
 * platform's own minimum touch size, and a `ListItem` is well past it while a chevron is not.
 */
@Composable
private fun ChoiceRow(
    label: String,
    value: String,
    choices: @Composable (dismiss: () -> Unit) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        ListItem(
            trailingContent = { Text(value, style = MaterialTheme.typography.labelLarge) },
            modifier = Modifier
                .fillMaxWidth()
                .clickable { open = true }
                .semantics { role = Role.DropdownList },
        ) { Text(label) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices { open = false }
        }
    }
}

/** One row that is a switch, with the switch itself as the row's trailing content. */
@Composable
private fun SwitchRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    ListItem(
        trailingContent = { Switch(checked = checked, onCheckedChange = onCheckedChange) },
        modifier = Modifier.fillMaxWidth(),
    ) { Text(label) }
}

/** How the transition modes are named on screen. */
private val PageTransition.labelRes: Int
    get() = when (this) {
        PageTransition.PAGE_CURL -> R.string.reader_transition_curl
        PageTransition.SLIDE -> R.string.reader_transition_slide
        PageTransition.FAST_FADE -> R.string.reader_transition_fade
        PageTransition.VERTICAL_SCROLL -> R.string.reader_transition_scroll_vertical
        PageTransition.HORIZONTAL_SCROLL -> R.string.reader_transition_scroll_horizontal
    }

/** Why a mode cannot run, in one line. */
private val TransitionUnavailability.labelRes: Int
    get() = when (this) {
        TransitionUnavailability.REDUCE_MOTION -> R.string.reader_transition_reduce_motion
        // A comic page is already an image, so this reason cannot arise here. It is named
        // rather than swallowed by an `else`, so that adding a third reason still breaks
        // this file rather than silently showing the wrong sentence.
        TransitionUnavailability.REFLOWABLE_TEXT -> R.string.reader_transition_reflowable
    }

/**
 * Which way the pages run, named the way a reader would say it.
 *
 * Right-to-left reuses the sentence TalkBack already reads out on entering a manga, because
 * it is the same fact and a second wording of it would be one to keep in step for nothing.
 */
private val ReadingDirection.labelRes: Int
    get() = when (this) {
        ReadingDirection.LEFT_TO_RIGHT -> R.string.reader_left_to_right
        ReadingDirection.RIGHT_TO_LEFT -> R.string.reader_right_to_left
    }

/**
 * How the fit modes are named on screen.
 *
 * The enum lives in `:core:model` and carries no resources: the domain has no business
 * holding UI copy.
 */
private val PageFit.labelRes: Int
    get() = when (this) {
        PageFit.SCREEN -> R.string.reader_fit_screen
        PageFit.WIDTH -> R.string.reader_fit_width
        PageFit.HEIGHT -> R.string.reader_fit_height
        PageFit.ORIGINAL -> R.string.reader_fit_original
    }
