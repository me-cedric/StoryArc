package app.storyarc.feature.epubreader

import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TextDecrease
import androidx.compose.material.icons.filled.TextIncrease
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AxisUnit
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.TransitionChoices
import app.storyarc.core.model.TransitionUnavailability
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.STEPS_PER_AXIS
import app.storyarc.core.model.setting
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.step
import app.storyarc.core.model.unit
import app.storyarc.core.model.value
import app.storyarc.core.model.values
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import java.text.NumberFormat
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
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(StoryArcSpace.gutter),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xl),
    ) {
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

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(R.string.theme_axis_bold_text),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            Switch(
                checked = values.isBold,
                onCheckedChange = { onChange(ThemeAxis.BOLD_TEXT, values.copy(isBold = it)) },
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
 * A few words in one face, for a card the size of a postage stamp.
 *
 * Words rather than lorem ipsum: a reader judges a typeface by shapes they know. Two
 * short lines fit a 48dp card and still show ascenders, descenders and a figure,
 * which is most of what distinguishes one serif from another.
 */
@Composable
private fun Specimen(
    typeface: ReaderTypeface,
    colour: Color,
    modifier: Modifier = Modifier,
    isBold: Boolean = false,
) {
    val family = typeface.fontFamily()

    // Sized in `dp`, so the system text size does not scale it. A specimen is a
    // *picture* of a typeface and the card it sits in is a fixed size: at twice the
    // system text size the words grew and the card clipped them, which is a specimen
    // that shows less of the face the larger the reader needs it.
    val fixed = with(LocalDensity.current) { SPECIMEN_DP.dp.toSp() }

    Column(
        // One picture, and not a sentence a screen reader should read twice per card.
        modifier = modifier.fillMaxWidth().clearAndSetSemantics {},
    ) {
        listOf(R.string.theme_specimen, R.string.theme_specimen_second).forEach { line ->
            Text(
                text = stringResource(line),
                style = MaterialTheme.typography.bodyMedium
                    .copy(fontFamily = family, fontSize = fixed),
                // Always explicit. A variable font's default instance is whatever its
                // `fvar` says, and upstream Bitter's is Thin — a specimen that let the
                // default stand would show a hairline and call it Bitter.
                fontWeight = if (isBold) FontWeight.Bold else FontWeight.Normal,
                color = colour,
                maxLines = 1,
            )
        }
    }
}

/**
 * The reader's own palette, as a seventh card in the same grid.
 *
 * Drawn from the same parts as a preset card, in its own colours, for the same
 * reason: a grid of samples reads at a glance and a grid of labels does not. It
 * carries the reader's name for the slot rather than the word "custom", because a
 * slot they named and cannot see the name of is not really theirs.
 */
@Composable
private fun CustomCard(
    palette: ReaderPalette,
    /** The face in force, since a colour slot has none of its own. */
    typeface: ReaderTypeface,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tokens = LocalStoryArcPalette.current
    val name = palette.name.trim().ifEmpty { stringResource(R.string.theme_page_colour_untitled) }

    Surface(
        modifier = modifier.semantics(mergeDescendants = true) {},
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(StoryArcRadius.md),
    ) {
        Column(
            modifier = Modifier
                .selectable(selected = true, role = Role.RadioButton, onClick = onSelect)
                .padding(StoryArcSpace.xs),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
                    .clip(RoundedCornerShape(StoryArcRadius.sm))
                    .background(Color(AndroidColor.parseColor(palette.background)))
                    .border(
                        width = 2.dp,
                        color = tokens.accent,
                        shape = RoundedCornerShape(StoryArcRadius.sm),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Specimen(
                    typeface = typeface,
                    colour = Color(AndroidColor.parseColor(palette.foreground)),
                    modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
                )
            }

            Text(
                text = name,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
                color = tokens.accent,
                maxLines = 1,
            )
        }
    }
}

/** Three across, which is what `ebook-reader`'s "three by two" means. */
private const val COLUMNS = 3

/**
 * How big a typeface specimen is drawn, in `dp` rather than `sp`.
 *
 * Fixed on purpose: see the note in `Specimen`.
 */
private const val SPECIMEN_DP = 14

/**
 * A slider's value as a screen reader should say it.
 *
 * The unit comes from the domain, so the two platforms cannot describe the same
 * slider differently. `NumberFormat` rather than `String.format`, because a comma
 * decimal separator is not a detail a French reader should have to work around.
 */
@Composable
private fun spokenValue(value: Double, unit: AxisUnit?): String {
    val number = remember {
        NumberFormat.getInstance().apply { maximumFractionDigits = 2 }
    }.format(value)
    return when (unit) {
        AxisUnit.MULTIPLE -> stringResource(R.string.theme_axis_value_multiple, number)
        AxisUnit.EM -> stringResource(R.string.theme_axis_value_em, number)
        null -> number
    }
}

/** One preset, previewed in its own colours. */
@Composable
private fun PresetCard(
    preset: ThemePreset,
    isActive: Boolean,
    isModified: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val sample = ReadingTheme(preset)

    // A tonal card, which is what `native-experience` asks Android for where iOS
    // gets glass. `selectable` rather than `clickable`: six mutually exclusive
    // options are a radio group, and TalkBack then says which one is chosen instead
    // of offering six identical buttons. Merged, so the card speaks as one thing.
    Surface(
        modifier = modifier.semantics(mergeDescendants = true) {},
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(StoryArcRadius.md),
    ) {
    Column(
        modifier = Modifier
            .selectable(selected = isActive, role = Role.RadioButton, onClick = onSelect)
            .padding(StoryArcSpace.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(RoundedCornerShape(StoryArcRadius.sm))
                .background(Color(AndroidColor.parseColor(sample.background)))
                .border(
                    width = if (isActive) 2.dp else 1.dp,
                    color = if (isActive) palette.accent else palette.borderSubtle,
                    shape = RoundedCornerShape(StoryArcRadius.sm),
                ),
            contentAlignment = Alignment.Center,
        ) {
            // Real letterforms in the preset's own face and colour.
            // `reading-themes` asks each card to preview "its own colours and
            // typeface", and a stack of grey rules — which is what this was — can
            // show a colour but never a face.
            Specimen(
                typeface = preset.values.typeface,
                colour = Color(AndroidColor.parseColor(sample.foreground)),
                isBold = preset.values.isBold,
                modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
            )
        }

        Text(
            text = stringResource(preset.labelRes),
            style = MaterialTheme.typography.labelLarge,
            // Weight as well as colour: colour is never the only signal.
            fontWeight = if (isActive) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isActive) palette.accent else palette.textSecondary,
            maxLines = 1,
        )

        if (isModified) {
            Text(
                text = stringResource(R.string.theme_modified),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
            )
        }
    }
    }
}

/** Where the size sits on its ladder. */
@Composable
private fun StepDots(position: Int, count: Int, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.hair, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { index ->
            Box(
                Modifier
                    .size(if (index == position) 7.dp else 5.dp)
                    .clip(CircleShape)
                    .background(if (index == position) palette.accent else palette.borderSubtle),
            )
        }
    }
}

internal val ThemePreset.labelRes: Int
    get() = when (this) {
        ThemePreset.ORIGINAL -> R.string.theme_preset_original
        ThemePreset.QUIET -> R.string.theme_preset_quiet
        ThemePreset.PAPER -> R.string.theme_preset_paper
        ThemePreset.BOLD -> R.string.theme_preset_bold
        ThemePreset.CALM -> R.string.theme_preset_calm
        ThemePreset.FOCUS -> R.string.theme_preset_focus
    }

internal val ReaderTypeface.labelRes: Int
    get() = when (this) {
        ReaderTypeface.PUBLISHER -> R.string.theme_typeface_publisher
        ReaderTypeface.SERIF -> R.string.theme_typeface_serif
        ReaderTypeface.SANS -> R.string.theme_typeface_sans
        // The bundled families go by their own names, which is how a reader
        // recognises them.
        ReaderTypeface.LITERATA -> R.string.theme_typeface_literata
        ReaderTypeface.SOURCE_SERIF -> R.string.theme_typeface_source_serif
        ReaderTypeface.EB_GARAMOND -> R.string.theme_typeface_eb_garamond
        ReaderTypeface.BITTER -> R.string.theme_typeface_bitter
        ReaderTypeface.ATKINSON_HYPERLEGIBLE -> R.string.theme_typeface_atkinson
    }

internal val ReaderTextAlignment.labelRes: Int
    get() = when (this) {
        ReaderTextAlignment.PUBLISHER -> R.string.theme_alignment_publisher
        ReaderTextAlignment.LEFT -> R.string.theme_alignment_left
        ReaderTextAlignment.JUSTIFIED -> R.string.theme_alignment_justified
    }

internal val ThemeAxis.labelRes: Int
    get() = when (this) {
        ThemeAxis.FONT_SIZE -> R.string.theme_axis_font_size
        ThemeAxis.FONT_FAMILY -> R.string.theme_axis_font_family
        ThemeAxis.BOLD_TEXT -> R.string.theme_axis_bold_text
        ThemeAxis.LINE_SPACING -> R.string.theme_axis_line_spacing
        ThemeAxis.CHARACTER_SPACING -> R.string.theme_axis_character_spacing
        ThemeAxis.WORD_SPACING -> R.string.theme_axis_word_spacing
        ThemeAxis.PARAGRAPH_SPACING -> R.string.theme_axis_paragraph_spacing
        ThemeAxis.MARGINS -> R.string.theme_axis_margins
        ThemeAxis.TEXT_ALIGNMENT -> R.string.theme_axis_text_alignment
    }
