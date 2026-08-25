package app.storyarc.feature.epubreader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
 */
@Composable
internal fun PageColourSection(
    palette: ReaderPalette?,
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

    /** The reader's name for the slot, or whatever it already had. */
    val chosenName = name.trim().ifEmpty { palette?.name ?: "" }

    fun adopt(candidate: ReaderPalette) {
        refused = if (onAdopt(candidate)) null else candidate.contrast
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
            onSelect = { adopt(ReaderPalette.derived(chosenName, it)) },
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
                adopt(ReaderPalette.derived(chosenName, hslHex(h, s, l)))
            },
        )

        if (palette != null) {
            Sample(palette)

            Text(
                text = stringResource(R.string.theme_page_colour_ratio, ratio(palette.contrast)),
                style = MaterialTheme.typography.labelLarge,
                color = tokens.textSecondary,
            )

            if (!palette.meetsAAA) {
                // Not a refusal — 4.5 is the floor and this pairing is above it. But
                // every built-in preset clears 7 to 1, so a reader should know when
                // their own choice does not.
                Text(
                    text = stringResource(R.string.theme_page_colour_below_aaa),
                    style = MaterialTheme.typography.labelLarge,
                    color = tokens.textTertiary,
                )
            }

            // `reading-themes`: "a seventh, user-named slot". The name is the
            // reader's, so it is a field rather than something generated for them.
            OutlinedTextField(
                value = name,
                onValueChange = {
                    name = it
                    adopt(palette.copy(name = it.trim()))
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
                onSelect = { adopt(palette.copy(foreground = it)) },
            )

            OutlinedButton(
                onClick = {
                    refused = null
                    onDiscard()
                },
            ) {
                Text(stringResource(R.string.theme_page_colour_clear))
            }
        }

        refused?.let {
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

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
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
