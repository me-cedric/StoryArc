package app.storyarc.feature.epubreader

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.control.ConnectedButtonGroup
import app.storyarc.core.designsystem.control.StoryArcSliderTrack
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.STEPS_PER_AXIS
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.unit
import app.storyarc.core.model.value
import app.storyarc.core.model.values
import kotlin.math.roundToInt

/**
 * Level two of the theme surface: the axes, over the publication's own text.
 *
 * `ebook-reader`, *The axes, over the reader's own text*:
 *
 * > **THEN** they appear on a surface of their own, over a specimen of the publication's own
 * > text in the active theme, which updates as an axis changes
 * > **AND** every axis states its current value in words or numbers beside its control,
 * > rather than as an unlabelled position on a track
 * > **AND** the axes offered are exactly those in `reading-themes`, with none added and none
 * > dropped
 *
 * **A destination, not a nested sheet, and this is the decision worth defending.** Material
 * never mentions a nested or stacked bottom sheet, so claiming it "discourages" one would be
 * inventing a citation. `design.md` records that, and records the three adjacent rules that
 * all lean the same way: the Dialogs page makes the full-screen variant "the only dialogs
 * over which other dialogs can appear"; the bottom-sheets page pushes "more complex tasks and
 * flows" off transient surfaces; the lists page says a compact-window second level "should
 * open a page with the details".
 *
 * The load-bearing one is predictive back, which is a *component-level* contract: Material's
 * bottom-sheet page specifies that a back swipe detaches the sheet and "Previous screen is
 * revealed in a preview". Two stacked modal sheets give that gesture two competing dismiss
 * targets and no correct preview. A destination has one.
 *
 * iOS does the opposite for the opposite reason: sheet-on-sheet is idiomatic there and the
 * platform animates it as a stack. The *behaviour* is identical — same axes, same values,
 * same reset — which is what the proposal means by one change on two platforms.
 *
 * The specimen is passed in rather than read again: the reader's position does not move while
 * either level is up, and reading the resource a second time would put a disk read inside the
 * transition.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ThemeAxesScreen(
    theme: ReadingTheme,
    values: ThemeValues,
    brightness: Float?,
    onChange: (ThemeAxis, ThemeValues) -> Unit,
    onSet: (ThemeAxis, Double) -> Unit,
    onBrightness: (Float) -> Unit,
    onRestore: () -> Unit,
    onLeavePublisherStyles: () -> Unit,
    onAdoptColours: (ReaderPalette) -> Boolean,
    onDiscardColours: () -> Unit,
    choices: TransitionChoices,
    onChooseTransition: (PageTransition) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    /** The chapter the reader is in, for the live preview to name. */
    chapter: String? = null,
    /** Words from where the reader is, read once when level one opened. */
    excerpt: String = "",
) {
    // The other half of being a destination: the system back gesture leaves level two and
    // returns to level one, with one dismiss target rather than two.
    BackHandler(onBack = onClose)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.theme_customise)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = stringResource(R.string.epub_close),
                        )
                    }
                },
            )
        },
    ) { insets ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(insets)
                .verticalScroll(rememberScrollState())
                .padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xl),
        ) {
            // First, because it is the thing every control below it changes, and
            // `ebook-reader` asks for it to update "as an axis changes".
            ThemePreview(theme = theme, values = values, title = chapter, excerpt = excerpt)

            PageTurnControl(choices, onChooseTransition)

            FontSizeControl(values, onChange)
            TypefaceControl(values, onChange)

            if (theme.preset.keepsPublisherStyles) {
                PublisherStylesNotice(onLeavePublisherStyles)
            } else {
                FineAxes(values, onSet)
                AlignmentControl(values, onChange)
                // A custom background cannot apply under Original, where the publisher's own
                // colours are the point — so it lives in the same branch as the other
                // overrides.
                PageColourSection(
                    palette = theme.custom,
                    onAdopt = onAdoptColours,
                    onDiscard = onDiscardColours,
                )
            }

            BrightnessControl(brightness, onBrightness)

            ResetToPreset(theme = theme, onRestore = onRestore)
        }
    }
}

/**
 * The way back to the preset the reader started from.
 *
 * `reading-themes`, *The reset names what it restores*: "the action names that preset — the
 * reader who modified Calm is offered Calm back, not an unnamed default", and *Resetting the
 * preset that is already unmodified*: the action is "absent rather than present and doing
 * nothing, because a control that never changes anything teaches a reader to distrust the
 * ones that do".
 *
 * **A plain low-emphasis `TextButton`, and no confirmation.** `design.md` is explicit that
 * **Material has nothing to say about reset-to-defaults** — no component, no pattern — and
 * that the Dialogs page's discard-unsaved-changes prompt is about abandoning edits rather
 * than restoring defaults, so dressing it up as one would be a false citation. No
 * confirmation, because the reset is immediately reversible by picking the preset again and a
 * dialogue over an undoable change is one a reader learns to dismiss unread.
 *
 * It does not leave the destination. `reading-themes` asks for the change to be "visible
 * behind the sheet without the sheet being dismissed", and the specimen at the top of this
 * screen is the nearer proof: it repaints as the values go back.
 */
@Composable
private fun ResetToPreset(theme: ReadingTheme, onRestore: () -> Unit) {
    if (!theme.isModified) return
    TextButton(onClick = onRestore, modifier = Modifier.fillMaxWidth()) {
        Text(
            text = stringResource(R.string.theme_restore_named, stringResource(theme.preset.labelRes)),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * How a page becomes the next page.
 *
 * `page-transitions` asks for its four modes in *both* readers. Two of them animate a
 * picture of a page, and a reflowable page is live web content — so those two are listed
 * with the reason rather than dropped, which is the spec's own "a mode is unavailable
 * for the content" scenario.
 *
 * Scroll here is Readium's own preference, not a container of ours: a web view that
 * already paginates and a scroll of ours would fight for the same gesture.
 */
@Composable
private fun PageTurnControl(
    choices: TransitionChoices,
    onChoose: (PageTransition) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_page_turn),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )

        choices.offered.forEach { mode ->
            val reason = choices.unavailable[mode]
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = choices.chosen == mode,
                        enabled = reason == null,
                        role = Role.RadioButton,
                        onClick = { onChoose(mode) },
                    )
                    .semantics(mergeDescendants = true) {}
                    .padding(vertical = StoryArcSpace.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(
                    selected = choices.chosen == mode,
                    onClick = null,
                    enabled = reason == null,
                )
                Column(modifier = Modifier.padding(start = StoryArcSpace.sm)) {
                    Text(
                        text = stringResource(mode.turnLabelRes),
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (reason == null) palette.textPrimary else palette.textTertiary,
                    )
                    if (reason != null) {
                        Text(
                            text = stringResource(reason.turnLabelRes),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textTertiary,
                        )
                    }
                }
            }
        }
    }
}

/**
 * How the page-turn modes are named in the theme sheet.
 *
 * A second copy of the comic reader's list, because the two features are separate
 * modules with separate resources — the alternative is a shared string module for five
 * words.
 */
private val PageTransition.turnLabelRes: Int
    get() = when (this) {
        PageTransition.PAGE_CURL -> R.string.theme_page_turn_curl
        PageTransition.SLIDE -> R.string.theme_page_turn_paginated
        PageTransition.FAST_FADE -> R.string.theme_page_turn_fade
        PageTransition.VERTICAL_SCROLL, PageTransition.HORIZONTAL_SCROLL ->
            R.string.theme_page_turn_scroll
    }

private val TransitionUnavailability.turnLabelRes: Int
    get() = when (this) {
        TransitionUnavailability.REDUCE_MOTION -> R.string.theme_page_turn_reduce_motion
        TransitionUnavailability.REFLOWABLE_TEXT -> R.string.theme_page_turn_reflowable
    }

/** Typeface and weight: the two axes that reach the page even under Original. */
@Composable
private fun TypefaceControl(
    values: ThemeValues,
    onChange: (ThemeAxis, ThemeValues) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_axis_font_family),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )

        // A column of rows, not a segmented control: eight faces will not fit across
        // a phone, and `reading-themes` calls this axis a picker.
        ReaderTypeface.entries.forEach { face ->
            Row(
                // One node, not a radio button beside two loose labels. `selectable`
                // rather than `clickable` so a screen reader says which face is
                // chosen, and merged so "Designed for low vision" is part of the
                // same utterance — a separate node is a label the reader who needs
                // it can walk straight past.
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = values.typeface == face,
                        role = Role.RadioButton,
                        onClick = {
                            onChange(ThemeAxis.FONT_FAMILY, values.copy(typeface = face))
                        },
                    )
                    .semantics(mergeDescendants = true) {}
                    .padding(vertical = StoryArcSpace.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(
                    selected = values.typeface == face,
                    onClick = null,
                )
                Column(modifier = Modifier.padding(start = StoryArcSpace.sm)) {
                    Text(
                        text = stringResource(face.labelRes),
                        // Each name drawn in the face it names. A picker whose
                        // options all look alike is a list of words rather than a
                        // choice.
                        style = MaterialTheme.typography.bodyMedium
                            .copy(fontFamily = face.fontFamily()),
                        color = palette.textPrimary,
                    )
                    if (face.isDesignedForLowVision) {
                        // `reading-themes`: labelled as such, because "an
                        // accessibility affordance presented as a style option gets
                        // missed by the people who need it".
                        Text(
                            text = stringResource(R.string.theme_typeface_low_vision),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textTertiary,
                        )
                    }
                }
            }
        }

        SwitchRow(
            label = stringResource(R.string.theme_axis_bold_text),
            supporting = stringResource(R.string.theme_axis_bold_text_note),
            checked = values.isBold,
            onCheckedChange = { onChange(ThemeAxis.BOLD_TEXT, values.copy(isBold = it)) },
        )

        // Beside bold rather than among the sliders: both are switches, and
        // `ebook-reader` lists hyphenation with the things a reader adjusts.
        SwitchRow(
            label = stringResource(R.string.theme_axis_hyphenation),
            supporting = stringResource(R.string.theme_axis_hyphenation_note),
            checked = values.isHyphenated,
            onCheckedChange = {
                onChange(ThemeAxis.HYPHENATION, values.copy(isHyphenated = it))
            },
        )
    }
}

/**
 * One switch axis, as a Material list item.
 *
 * `design.md`: `ListItem(content =, supportingContent =, trailingContent = Switch)`, with
 * `toggleable` on the item. Material authorises the supporting line on a list item; the
 * Switch page requires only an inline label and says nothing about supporting text, so the
 * second line is the list's affordance rather than the switch's.
 *
 * **The item is the toggleable, not the switch inside it.** A switch on its own is an unnamed
 * node — its label is a sibling, and a screen reader landing on it hears a bare on/off.
 * `toggleable` merges the label and the supporting line in, states the role, and widens the
 * target to the whole row; `onCheckedChange = null` on the switch is what stops the two from
 * both claiming the gesture.
 *
 * The supporting line is what `reading-themes` means by an axis stating its value in words:
 * a switch's *value* is its on/off state, which the switch itself carries, and what a reader
 * cannot get from it is what turning it on does.
 */
@Composable
private fun SwitchRow(
    label: String,
    supporting: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    ListItem(
        supportingContent = { Text(supporting) },
        trailingContent = { Switch(checked = checked, onCheckedChange = null) },
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange),
    ) { Text(label) }
}

/**
 * The sliders. One loop rather than five blocks, because the domain answers every
 * question a slider asks: its range, its value, and how to set it.
 */
@Composable
private fun FineAxes(
    values: ThemeValues,
    onSet: (ThemeAxis, Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        Text(
            text = stringResource(R.string.theme_spacing),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )

        ThemeAxis.entries.forEach { axis ->
            val range = axis.sliderRange ?: return@forEach
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
                val spoken = spokenValue(values.value(axis), axis.unit)
                val name = stringResource(axis.labelRes)

                // The name on the left, the value on the right.
                //
                // `reading-themes`: "its current value is stated beside it in the reader's
                // own language and units, and updates as the control moves **AND** the value
                // is available to assistive technology as part of the control rather than as
                // a separate unlabelled element". Both halves are load-bearing in opposite
                // directions, which is why the visible value is cleared of semantics and the
                // slider carries the reading instead: a label left visible to TalkBack lands
                // between the axis's name and its slider and reads a bare number.
                //
                // There is no value-label API in `SliderDefaults` at all, and Material
                // sanctions this arrangement independently: "If the value is shown elsewhere,
                // the indicator is not required."
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = name,
                        style = MaterialTheme.typography.labelLarge,
                        color = palette.textSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = spoken,
                        style = MaterialTheme.typography.labelLarge,
                        color = palette.textTertiary,
                        modifier = Modifier.clearAndSetSemantics {},
                    )
                }

                Slider(
                    value = values.value(axis).toFloat(),
                    onValueChange = { onSet(axis, it.toDouble()) },
                    valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
                    // Discrete, so TalkBack's adjust action moves the value by
                    // something a reader can notice, and so a drag submits ten
                    // preference changes to the renderer rather than one per frame.
                    steps = STEPS_PER_AXIS - 1,
                    // Centred where the preset's own value sits mid-range, which is what the
                    // centred variant is for: character spacing, word spacing and margins all
                    // open in the middle of their range and are moved in either direction, so
                    // a track filled from the left says the reader has *raised* an axis they
                    // have only nudged. Stable API, verified by `javap` over
                    // `material3-1.5.0-alpha26.aar`.
                    // The gap between the handle and the rail goes, on both variants. See
                    // `StoryArcSliderTrack`: at either end of an axis's travel one half of
                    // the rail has no width, and the handle is then floating beside a rail
                    // it is not touching.
                    track = { state ->
                        if (axis in CENTRED_AXES) {
                            SliderDefaults.CenteredTrack(
                                sliderState = state,
                                thumbTrackGapSize = 0.dp,
                            )
                        } else {
                            StoryArcSliderTrack(state)
                        }
                    },
                    // The name and the reading both belong on the slider itself. The
                    // heading beside it is a sibling node, so a screen reader landing
                    // on the slider would otherwise announce a bare percentage of a
                    // range and never say which axis it belongs to.
                    modifier = Modifier.semantics {
                        contentDescription = name
                        stateDescription = spoken
                    },
                )
            }
        }
    }
}

@Composable
private fun AlignmentControl(
    values: ThemeValues,
    onChange: (ThemeAxis, ThemeValues) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_axis_text_alignment),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        // A connected button group, not the segmented row this was. Material 3 Expressive
        // says the baseline segmented button "is no longer recommended" and nothing in the
        // build says so — `SegmentedButton` carries no deprecation at material3
        // 1.5.0-alpha26, so this was silent for as long as it stood.
        //
        // Read once into a list, because the group's shapes are keyed by position: the index
        // it reports has to index the same list the labels came from. Every alignment is
        // always offered — publisher styles are answered by `PublisherStylesNotice` above,
        // not by dropping an option — but a filtered list here would otherwise reshape
        // silently.
        val alignments = ReaderTextAlignment.entries
        ConnectedButtonGroup(
            options = alignments.map { stringResource(it.labelRes) },
            selectedIndex = alignments.indexOf(values.textAlignment),
            onSelect = { index ->
                onChange(ThemeAxis.TEXT_ALIGNMENT, values.copy(textAlignment = alignments[index]))
            },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * `reading-themes`: reader-local, and it does not permanently move the device's own.
 * On Android the value is a window attribute, so leaving reverts it by itself.
 */
@Composable
private fun BrightnessControl(
    brightness: Float?,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_brightness),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )
        val percent = stringResource(
            R.string.theme_brightness_percent,
            ((brightness ?: 0.5f) * 100).roundToInt(),
        )
        val name = stringResource(R.string.theme_brightness)
        Slider(
            // Until the reader moves it there is no reader-local value, and the
            // window is following the device. Half-way is the honest resting
            // position for a control that has not been used.
            value = brightness ?: 0.5f,
            onValueChange = onChange,
            valueRange = 0.1f..1f,
            modifier = Modifier.semantics {
                contentDescription = name
                stateDescription = percent
            },
        )
    }
}

/** `reading-themes`: stepped, with the position shown, never a free slider. */
@Composable
private fun FontSizeControl(
    values: ThemeValues,
    onChange: (ThemeAxis, ThemeValues) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val label = stringResource(R.string.theme_font_size_percent, values.fontSize.percent)
    // Position first, then the percentage. `native-experience` asks the stepper to
    // announce "its position out of the total rather than only larger" — a
    // percentage alone never says how much room is left on the ladder.
    val spoken = stringResource(
        R.string.theme_font_size_position,
        values.fontSize.position + 1,
        FontSizeStep.count,
    ) + ", " + label

    Column(
        // One control, spoken as one: two unlabelled buttons make a screen reader
        // hunt for the thing they adjust.
        modifier = modifier.semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        Text(
            text = stringResource(R.string.theme_font_size),
            style = MaterialTheme.typography.titleMedium,
            color = palette.textPrimary,
        )

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        ) {
            IconButton(
                onClick = { onChange(ThemeAxis.FONT_SIZE, values.copy(fontSize = values.fontSize.previous)) },
                enabled = values.fontSize != FontSizeStep.entries.first(),
            ) {
                Icon(
                    imageVector = Icons.Filled.TextDecrease,
                    contentDescription = stringResource(R.string.theme_font_size_smaller),
                    tint = palette.accent,
                )
            }

            StepDots(
                position = values.fontSize.position,
                count = FontSizeStep.count,
                modifier = Modifier.weight(1f),
            )

            IconButton(
                onClick = { onChange(ThemeAxis.FONT_SIZE, values.copy(fontSize = values.fontSize.next)) },
                enabled = values.fontSize != FontSizeStep.entries.last(),
            ) {
                Icon(
                    imageVector = Icons.Filled.TextIncrease,
                    contentDescription = stringResource(R.string.theme_font_size_larger),
                    tint = palette.accent,
                )
            }
        }

        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )
    }
}

/** What Original costs, said once rather than implied by dead sliders. */
@Composable
private fun PublisherStylesNotice(onLeave: () -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.lg),
    ) {
        Column(
            modifier = Modifier.padding(StoryArcSpace.md),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            Text(
                text = stringResource(R.string.theme_publisher_styles_title),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            Text(
                text = stringResource(R.string.theme_publisher_styles_reason),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
            // The single action the spec asks for. It names what it does rather than
            // saying "fix": turning publisher styles off is a real choice about
            // whose typography wins.
            OutlinedButton(onClick = onLeave) {
                Text(stringResource(R.string.theme_publisher_styles_action))
            }
            ThemeAxis.entries.filter { it.requiresPublisherStylesOff }.forEach { axis ->
                Text(
                    text = stringResource(axis.labelRes),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
        }
    }
}

/**
 * The axes whose published value sits in the middle of their range.
 *
 * `design.md`: `SliderDefaults.CenteredTrack` "for character spacing, word spacing and
 * margins, whose defaults sit mid-range". Named here rather than asked of the domain, because
 * it is a fact about how the *control* should look and `:core:model` has no business holding
 * one.
 *
 * The slider icons stay outside the track for the other half of that note: the Expressive
 * inset icon has no API, and Material forbids it below a 40dp track and on centred sliders
 * anyway.
 */
private val CENTRED_AXES = setOf(
    ThemeAxis.CHARACTER_SPACING,
    ThemeAxis.WORD_SPACING,
    ThemeAxis.MARGINS,
)
