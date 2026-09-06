package app.storyarc.feature.epubreader

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ReaderPalette
import app.storyarc.core.model.ReadingContrast
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import app.storyarc.core.model.SUGGESTED_FOREGROUNDS
import java.text.NumberFormat
import kotlin.math.roundToInt

/**
 * A reading background of the reader's own, kept legible.
 *
 * `reading-themes` asks for four things here and it is easy to build three of them:
 * swatches, a picker, a text colour derived at 7 to 1, and a refusal below 4.5 to 1
 * **with the measured ratio stated**. The last one is why the ratio is on screen at
 * all times rather than only when something goes wrong — a number that appears only
 * to scold is a number the reader has no reason to trust.
 *
 * It is a seventh slot, not a seventh preset: choosing it keeps the typography the
 * reader already has, and tapping one of the six leaves it behind.
 *
 * The picker is three sliders rather than a wheel. Compose has no colour picker, and
 * the sheet already speaks in Material sliders — a hand-rolled hue wheel would be
 * more code and less familiar. ponytail: HSL sliders; a wheel only if a reader asks
 * for one.
 *
 * A pairing is also **shown before it is applied**. Every control here sets a pending
 * pairing that the sample, the band and the ratio describe; one confirmation puts it on the
 * page. The refusal is unchanged and still happens on that confirmation, because a pairing
 * has to be asked for before it can be turned down.
 *
 * @param inForce the pairing the page is being drawn with, or null while the preset's own
 *   colours are.
 */
@Composable
internal fun PageColourSection(
    inForce: ReaderPalette?,
    onAdopt: (ReaderPalette) -> Boolean,
    onDiscard: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tokens = LocalStoryArcPalette.current

    /** The ratio of the pairing that was last turned down, so it can be stated. */
    var refused by remember { mutableStateOf<Double?>(null) }
    var name by remember { mutableStateOf("") }
    var hue by remember { mutableStateOf(40f) }
    var saturation by remember { mutableStateOf(0.3f) }
    var lightness by remember { mutableStateOf(0.95f) }

    /** A pairing the reader has chosen and not yet applied. */
    var pending by remember { mutableStateOf<ReaderPalette?>(null) }

    /** What the sample, the band and the ratio describe. */
    val palette = previewedPairing(pending = pending, inForce = inForce)

    /** The reader's name for the slot, or whatever it already had. */
    val chosenName = name.trim().ifEmpty { palette?.name ?: "" }

    /** Shows a pairing without putting it on the page. */
    fun preview(candidate: ReaderPalette) {
        pending = candidate
        // A refusal measured a pairing that is no longer the one being described.
        refused = null
    }

    fun adopt(candidate: ReaderPalette) {
        refused = if (onAdopt(candidate)) null else candidate.contrast
        // What was pending is now in force, and `inForce` describes it from here.
        if (refused == null) pending = null
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Text(
            text = stringResource(R.string.theme_page_colour),
            style = MaterialTheme.typography.titleMedium,
            color = tokens.textPrimary,
        )

        SwatchRow(
            colours = SUGGESTED_BACKGROUNDS,
            selected = palette?.background,
            onSelect = { preview(ReaderPalette.derived(chosenName, it)) },
        )

        Text(
            text = stringResource(R.string.theme_page_colour_pick),
            style = MaterialTheme.typography.labelLarge,
            color = tokens.textSecondary,
        )
        HslSliders(
            hue = hue,
            saturation = saturation,
            lightness = lightness,
            onChange = { h, s, l ->
                hue = h
                saturation = s
                lightness = l
                preview(ReaderPalette.derived(chosenName, hslHex(h, s, l)))
            },
        )

        if (palette != null) {
            Sample(palette)

            // The band first, because it is what a reader can act on, and the measured
            // ratio under it, because the spec keeps the number and a bug report needs
            // it. `textPrimary` against the ratio line's `textSecondary` says which of
            // the two is meant to be read first.
            Text(
                text = stringResource(ReadingComfort.band(palette.contrast).label),
                style = MaterialTheme.typography.labelLarge,
                color = tokens.textPrimary,
            )

            Text(
                text = stringResource(R.string.theme_page_colour_ratio, ratio(palette.contrast)),
                style = MaterialTheme.typography.labelLarge,
                color = tokens.textSecondary,
            )

            // `reading-themes`: "a seventh, user-named slot". The name is the
            // reader's, so it is a field rather than something generated for them.
            OutlinedTextField(
                value = name,
                onValueChange = {
                    name = it
                    preview(palette.copy(name = it.trim()))
                },
                label = { Text(stringResource(R.string.theme_page_colour_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Text(
                text = stringResource(R.string.theme_page_colour_text_colour),
                style = MaterialTheme.typography.labelLarge,
                color = tokens.textSecondary,
            )
            SwatchRow(
                colours = SUGGESTED_FOREGROUNDS,
                selected = palette.foreground,
                onSelect = { preview(palette.copy(foreground = it)) },
            )

            // Present only while something is waiting, because a control that never changes
            // anything teaches a reader to distrust the ones that do — the rule
            // `reading-themes` states for the named reset.
            pending?.let { candidate ->
                Button(onClick = { adopt(candidate) }) {
                    Text(stringResource(R.string.theme_page_colour_apply))
                }
            }

            OutlinedButton(
                onClick = {
                    pending = null
                    refused = null
                    onDiscard()
                },
            ) {
                Text(stringResource(R.string.theme_page_colour_clear))
            }
        }

        refused?.let {
            // The band leads here too, so the refusal opens with what the reader can
            // act on rather than with arithmetic.
            Text(
                text = stringResource(ReadingComfort.band(it).label),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.error,
            )

            // The number, not just the word. `reading-themes`: refused "with the
            // measured ratio stated", because "that is not allowed" without a number
            // is an obstacle rather than an explanation.
            Text(
                text = stringResource(
                    R.string.theme_page_colour_refused,
                    ratio(it),
                    ratio(ReadingContrast.AA),
                ),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}

/**
 * What the sample, the band and the ratio describe.
 *
 * The pending pairing where there is one, and the pairing in force otherwise. A function
 * rather than an expression inside the composable, so a JVM test can ask it.
 *
 * iOS mirrors this in `PageColourSection.previewed(pending:inForce:)`.
 */
internal fun previewedPairing(pending: ReaderPalette?, inForce: ReaderPalette?): ReaderPalette? =
    pending ?: inForce

/**
 * What a pairing will be like to read, in words a reader can act on.
 *
 * A reader choosing a background colour does not know what "4.7 to 1" means. A number
 * nobody can interpret is not information; it is decoration that looks like
 * information. So the sheet leads with one of three bands and states the measured ratio
 * after it. Nothing is dropped: `reading-themes` requires a refused pairing to be
 * stated "with the measured ratio stated", a reader who is refused deserves to know by
 * how much, and a developer reading a bug report needs the number.
 *
 * **The two boundaries are the domain's own, not new ones.** [ReadingContrast.AAA] at
 * 7, which a derived text colour aims for and every built-in preset clears, and
 * [ReadingContrast.AA] at 4.5, below which the sheet refuses the pairing outright. A
 * band drawn at any other number would let the words and the refusal disagree about the
 * same pairing — the sheet calling a pairing comfortable and then refusing it.
 *
 * The words are about reading rather than about the numbers behind them, because a
 * reader wants to know whether a chapter will be comfortable, not whether a guideline
 * is met. They replace `theme_page_colour_below_aaa`, which said the same thing in the
 * arithmetic the reader could not read.
 *
 * ponytail: it lives beside the one section that draws it rather than in `core:model`,
 * because it is a wording decision over a number the domain already gives. Move it when
 * a second surface asks the same question.
 *
 * iOS mirrors this in `PageColourSection.swift`.
 */
internal enum class ReadingComfort(@StringRes val label: Int) {
    /** 7 to 1 and above. */
    EASY(R.string.theme_page_colour_band_easy),

    /** 4.5 to 1 up to 7 to 1. Usable, and the sheet says what it costs. */
    TIRING(R.string.theme_page_colour_band_tiring),

    /** Below 4.5 to 1. Refused. */
    FAINT(R.string.theme_page_colour_band_faint),
    ;

    companion object {
        fun band(ratio: Double): ReadingComfort = when {
            ratio >= ReadingContrast.AAA -> EASY
            ratio >= ReadingContrast.AA -> TIRING
            else -> FAINT
        }
    }
}

/** Three lines of real text in the pairing, so the reader judges it as text. */
@Composable
private fun Sample(palette: ReaderPalette, modifier: Modifier = Modifier) {
    val tokens = LocalStoryArcPalette.current
    val description = stringResource(R.string.theme_page_colour_sample_label)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(StoryArcRadius.sm))
            .background(hexColour(palette.background))
            .border(
                width = 1.dp,
                color = tokens.borderSubtle,
                shape = RoundedCornerShape(StoryArcRadius.sm),
            )
            .padding(StoryArcSpace.sm)
            // Read aloud as one thing, and as what it is rather than as three lines
            // of filler a screen reader would otherwise recite.
            .semantics(mergeDescendants = true) { contentDescription = description },
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        repeat(3) {
            Text(
                text = stringResource(R.string.theme_page_colour_sample),
                style = MaterialTheme.typography.bodySmall,
                color = hexColour(palette.foreground),
                maxLines = 1,
            )
        }
    }
}

/**
 * A row of colours, selection shown by a ring rather than a tick.
 *
 * A tick would have to be one colour or the other and would vanish against half the
 * swatches; a ring in the app's accent never does.
 */
@Composable
private fun SwatchRow(
    colours: List<String>,
    selected: String?,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tokens = LocalStoryArcPalette.current

    // `FlowRow`, because eight fixed swatches need 312dp and a 320dp phone leaves
    // 280dp after the sheet's padding, so a plain `Row` puts the last colours past
    // the screen edge with no way to reach them.
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        colours.forEach { hex ->
            val isActive = selected?.equals(hex, ignoreCase = true) == true
            val description = stringResource(R.string.theme_page_colour_swatch, hex)
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(hexColour(hex))
                    .border(
                        width = if (isActive) 3.dp else 1.dp,
                        color = if (isActive) tokens.accent else tokens.borderSubtle,
                        shape = CircleShape,
                    )
                    .selectable(
                        selected = isActive,
                        role = Role.RadioButton,
                        onClick = { onSelect(hex) },
                    )
                    .semantics { contentDescription = description },
            )
        }
    }
}

/** Hue, saturation and lightness, each named so a screen reader can say which. */
@Composable
private fun HslSliders(
    hue: Float,
    saturation: Float,
    lightness: Float,
    onChange: (Float, Float, Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier) {
        NamedSlider(R.string.theme_page_colour_hue, hue, 0f..360f) {
            onChange(it, saturation, lightness)
        }
        NamedSlider(R.string.theme_page_colour_saturation, saturation, 0f..1f) {
            onChange(hue, it, lightness)
        }
        NamedSlider(R.string.theme_page_colour_lightness, lightness, 0f..1f) {
            onChange(hue, saturation, it)
        }
    }
}

@Composable
private fun NamedSlider(
    labelRes: Int,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit,
) {
    val tokens = LocalStoryArcPalette.current
    val name = stringResource(labelRes)

    Column {
        Text(
            text = name,
            style = MaterialTheme.typography.labelLarge,
            color = tokens.textSecondary,
        )
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = range,
            modifier = Modifier.semantics { contentDescription = name },
        )
    }
}

/** `#rrggbb` from hue in degrees and saturation and lightness in 0…1. */
internal fun hslHex(hue: Float, saturation: Float, lightness: Float): String {
    val colour = Color.hsl(hue.coerceIn(0f, 360f), saturation, lightness)
    val channels = listOf(colour.red, colour.green, colour.blue)
        .map { (it * 255).roundToInt().coerceIn(0, 255) }
    return "#" + channels.joinToString("") { "%02X".format(it) }
}

private fun hexColour(hex: String): Color {
    val text = hex.removePrefix("#")
    val value = text.toLongOrNull(16) ?: return Color.Unspecified
    return Color(
        red = ((value shr 16) and 0xFF) / 255f,
        green = ((value shr 8) and 0xFF) / 255f,
        blue = (value and 0xFF) / 255f,
    )
}

private fun ratio(value: Double): String =
    NumberFormat.getInstance().apply { maximumFractionDigits = 1; minimumFractionDigits = 1 }
        .format(value)
