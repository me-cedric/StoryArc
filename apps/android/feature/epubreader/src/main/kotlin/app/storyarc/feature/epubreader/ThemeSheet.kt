package app.storyarc.feature.epubreader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
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
 * The reading-theme sheet.
 *
 * `ebook-reader` and `reading-themes` between them ask for a preset grid, a stepped
 * font size with a visible position, and — the part that is easy to skip — an axis
 * that cannot reach the page shown "unavailable with a one-line reason and a single
 * action that turns publisher styles off". Not hidden, and not a live control that
 * does nothing.
 *
 * The fine axes — line, character, word and paragraph spacing, margins, alignment,
 * custom background — are Phase 3.5 and 3.7 of the change and are not here yet.
 * What is here is the first level the spec describes. iOS's `ThemeSheet` is the same
 * sheet.
 */
@Composable
internal fun ThemeSheet(
    theme: ReadingTheme,
    values: ThemeValues,
    brightness: Float?,
    onAdopt: (ThemePreset) -> Unit,
    onChange: (ThemeAxis, ThemeValues) -> Unit,
    onSet: (ThemeAxis, Double) -> Unit,
    onBrightness: (Float) -> Unit,
    onRestore: () -> Unit,
    onLeavePublisherStyles: () -> Unit,
    onAdoptColours: (ReaderPalette) -> Boolean,
    onDiscardColours: () -> Unit,
    choices: TransitionChoices,
    onChooseTransition: (PageTransition) -> Unit,
    modifier: Modifier = Modifier,
    /** The chapter the reader is in, for the live preview to name. */
    chapter: String? = null,
    /**
     * Words from where the reader is, read once when the sheet opens. Empty until the
     * resource comes back, and empty for good on a publication it cannot be read from --
     * the preview shows its sample paragraph in both cases.
     */
    excerpt: String = "",
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(StoryArcSpace.gutter),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xl),
    ) {
        // First, because it is the thing every control below it changes.
        ThemePreview(theme = theme, values = values, title = chapter, excerpt = excerpt)

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.theme_presets),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            if (theme.isModified) {
                TextButton(onClick = onRestore) {
                    Text(stringResource(R.string.theme_restore))
                }
            }
        }

        // Three by two, each card in its own colours. `ebook-reader`: the grid
        // previews "each preset in its own colours — six samples, not six labels".
        //
        // Rows rather than a `LazyVerticalGrid`: there are six or seven known items and
        // this is already inside a scrolling column, so a lazy grid buys nothing and
        // costs a *fixed height* — which at twice the system text size clipped the
        // labels off the bottom of every card. Rows take the height their content needs.
        val cards: List<@Composable (Modifier) -> Unit> = buildList {
            ThemePreset.entries.forEach { preset ->
                add { cardModifier ->
                    PresetCard(
                        preset = preset,
                        isActive = theme.preset == preset && !theme.isCustom,
                        isModified = theme.preset == preset && theme.isModified,
                        onSelect = { onAdopt(preset) },
                        modifier = cardModifier,
                    )
                }
            }
            // The seventh slot, present only once the reader has made one.
            // `reading-themes` puts it "alongside the six presets rather than
            // overwriting one", so it is a seventh card and not a replaced one.
            theme.custom?.let { custom ->
                add { cardModifier ->
                    CustomCard(
                        palette = custom,
                        typeface = values.typeface,
                        onSelect = { onAdoptColours(custom) },
                        modifier = cardModifier,
                    )
                }
            }
        }

        cards.chunked(COLUMNS).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                row.forEach { card -> card(Modifier.weight(1f)) }
                // A short last row keeps its cards the same width as a full one.
                repeat(COLUMNS - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }

        PageTurnControl(choices, onChooseTransition)

        FontSizeControl(values, onChange)
        TypefaceControl(values, onChange)

        if (theme.preset.keepsPublisherStyles) {
            PublisherStylesNotice(onLeavePublisherStyles)
        } else {
            FineAxes(values, onSet)
            AlignmentControl(values, onChange)
            // A custom background cannot apply under Original, where the publisher's
            // own colours are the point — so it lives in the same branch as the
            // other overrides.
            PageColourSection(
                palette = theme.custom,
                onAdopt = onAdoptColours,
                onDiscard = onDiscardColours,
            )
        }

        BrightnessControl(brightness, onBrightness)
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

        // The row is the toggleable, not the switch inside it. A switch on its own is
        // an unnamed node — its label is a sibling, and a screen reader landing on it
        // hears a bare on/off. `toggleable` merges the label in and widens the target.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = values.isBold,
                    role = Role.Switch,
                    onValueChange = { onChange(ThemeAxis.BOLD_TEXT, values.copy(isBold = it)) },
                ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.theme_axis_bold_text),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            Switch(
                checked = values.isBold,
                onCheckedChange = null,
            )
        }

        // Beside bold rather than among the sliders: both are switches, and
        // `ebook-reader` lists hyphenation with the things a reader adjusts.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .toggleable(
                    value = values.isHyphenated,
                    role = Role.Switch,
                    onValueChange = {
                        onChange(ThemeAxis.HYPHENATION, values.copy(isHyphenated = it))
                    },
                ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.theme_axis_hyphenation),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            Switch(
                checked = values.isHyphenated,
                onCheckedChange = null,
            )
        }
    }
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
                Text(
                    text = stringResource(axis.labelRes),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                )
                val spoken = spokenValue(values.value(axis), axis.unit)
                val name = stringResource(axis.labelRes)
                Slider(
                    value = values.value(axis).toFloat(),
                    onValueChange = { onSet(axis, it.toDouble()) },
                    valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
                    // Discrete, so TalkBack's adjust action moves the value by
                    // something a reader can notice, and so a drag submits ten
                    // preference changes to the renderer rather than one per frame.
                    steps = STEPS_PER_AXIS - 1,
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
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            ReaderTextAlignment.entries.forEachIndexed { index, value ->
                SegmentedButton(
                    selected = values.textAlignment == value,
                    onClick = { onChange(ThemeAxis.TEXT_ALIGNMENT, values.copy(textAlignment = value)) },
                    shape = SegmentedButtonDefaults.itemShape(
                        index,
                        ReaderTextAlignment.entries.size,
                    ),
                ) {
                    Text(stringResource(value.labelRes))
                }
            }
        }
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
 * The theme sheet, in the platform's own modal bottom sheet.
 *
 * `native-experience` wants the sheet to look like the platform's; iOS gets a
 * detented sheet on Liquid Glass and Android gets this.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ThemeBottomSheet(
    theme: ReadingTheme,
    values: ThemeValues,
    brightness: Float?,
    onAdopt: (ThemePreset) -> Unit,
    onChange: (ThemeAxis, ThemeValues) -> Unit,
    onSet: (ThemeAxis, Double) -> Unit,
    onBrightness: (Float) -> Unit,
    onRestore: () -> Unit,
    onLeavePublisherStyles: () -> Unit,
    onAdoptColours: (ReaderPalette) -> Boolean,
    onDiscardColours: () -> Unit,
    choices: TransitionChoices,
    onChooseTransition: (PageTransition) -> Unit,
    onDismiss: () -> Unit,
    chapter: String? = null,
    excerpt: String = "",
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        ThemeSheet(
            theme = theme,
            values = values,
            brightness = brightness,
            onAdopt = onAdopt,
            onChange = onChange,
            onSet = onSet,
            onBrightness = onBrightness,
            onRestore = onRestore,
            onLeavePublisherStyles = onLeavePublisherStyles,
            onAdoptColours = onAdoptColours,
            onDiscardColours = onDiscardColours,
            choices = choices,
            onChooseTransition = onChooseTransition,
            chapter = chapter,
            excerpt = excerpt,
        )
    }
}
