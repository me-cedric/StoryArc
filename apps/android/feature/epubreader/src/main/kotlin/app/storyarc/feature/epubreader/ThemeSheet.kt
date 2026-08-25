package app.storyarc.feature.epubreader

import android.graphics.Color as AndroidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.FontSizeStep
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.setting
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.value
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues

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
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.height(200.dp),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            items(ThemePreset.entries) { preset ->
                PresetCard(
                    preset = preset,
                    isActive = theme.preset == preset,
                    isModified = theme.preset == preset && theme.isModified,
                    onSelect = { onAdopt(preset) },
                )
            }
        }

        FontSizeControl(values, onChange)
        TypefaceControl(values, onChange)

        if (theme.preset.keepsPublisherStyles) {
            PublisherStylesNotice(onLeavePublisherStyles)
        } else {
            FineAxes(values, onSet)
            AlignmentControl(values, onChange)
        }

        BrightnessControl(brightness, onBrightness)
    }
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
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        onChange(ThemeAxis.FONT_FAMILY, values.copy(typeface = face))
                    }
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
                        style = MaterialTheme.typography.bodyMedium,
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
                Slider(
                    value = values.value(axis).toFloat(),
                    onValueChange = { onSet(axis, it.toDouble()) },
                    valueRange = range.start.toFloat()..range.endInclusive.toFloat(),
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
        Slider(
            // Until the reader moves it there is no reader-local value, and the
            // window is following the device. Half-way is the honest resting
            // position for a control that has not been used.
            value = brightness ?: 0.5f,
            onValueChange = onChange,
            valueRange = 0.1f..1f,
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

    Column(
        // One control, spoken as one: two unlabelled buttons make a screen reader
        // hunt for the thing they adjust.
        modifier = modifier.semantics(mergeDescendants = true) { contentDescription = label },
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

    Column(
        modifier = modifier.clickable(onClick = onSelect),
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
            // Three lines of nothing in the preset's own text colour: a sample of
            // the pairing, which is what the reader is choosing.
            Column(
                modifier = Modifier.padding(horizontal = StoryArcSpace.sm),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                repeat(3) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(2.dp)
                            .background(Color(AndroidColor.parseColor(sample.foreground))),
                    )
                }
            }
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

private val ThemePreset.labelRes: Int
    get() = when (this) {
        ThemePreset.ORIGINAL -> R.string.theme_preset_original
        ThemePreset.QUIET -> R.string.theme_preset_quiet
        ThemePreset.PAPER -> R.string.theme_preset_paper
        ThemePreset.BOLD -> R.string.theme_preset_bold
        ThemePreset.CALM -> R.string.theme_preset_calm
        ThemePreset.FOCUS -> R.string.theme_preset_focus
    }

private val ReaderTypeface.labelRes: Int
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

private val ReaderTextAlignment.labelRes: Int
    get() = when (this) {
        ReaderTextAlignment.PUBLISHER -> R.string.theme_alignment_publisher
        ReaderTextAlignment.LEFT -> R.string.theme_alignment_left
        ReaderTextAlignment.JUSTIFIED -> R.string.theme_alignment_justified
    }

private val ThemeAxis.labelRes: Int
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
