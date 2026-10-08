package app.storyarc.feature.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.control.StoryArcSliderTrack
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ImageAdjustments
import app.storyarc.core.model.SUGGESTED_BACKGROUNDS
import app.storyarc.core.model.SUGGESTED_BACKGROUND_NAMES
import kotlin.math.roundToInt

/** Opens the adjustment controls, and shows whether anything is applied. */
@Composable
internal fun AdjustButton(isNeutral: Boolean, onOpen: () -> Unit) {
    IconButton(onClick = onOpen, modifier = Modifier.padding(StoryArcSpace.md)) {
        Surface(
            color = if (isNeutral) {
                LocalStoryArcPalette.current.scrim.copy(alpha = 0.6f)
            } else {
                // Marked while something is applied, so a reader who wonders why the page
                // looks like that can see that they asked for it.
                LocalStoryArcPalette.current.accent
            },
            shape = CircleShape,
        ) {
            Icon(
                imageVector = Icons.Filled.Tune,
                contentDescription = stringResource(R.string.reader_adjust),
                tint = Color.White,
                modifier = Modifier.padding(StoryArcSpace.sm),
            )
        }
    }
}

/**
 * The controls for a badly scanned page.
 *
 * `comic-reader`: "brightness, contrast, sharpness, colour inversion, and greyscale ... with
 * a live preview". The preview is the page behind the sheet, which is why this is a bottom
 * sheet rather than a screen: a control that hides what it changes cannot be judged.
 *
 * iOS's `AdjustmentsSheet` is the same sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AdjustmentsSheet(
    adjustments: ImageAdjustments,
    shelf: String,
    cropsThisPage: Boolean,
    onCropThisPage: (Boolean) -> Unit,
    onChange: (ImageAdjustments) -> Unit,
    onDismiss: () -> Unit,
    /** D34: the colour behind the page, and the reader-local brightness beside it. */
    matte: String?,
    onChooseMatte: (String?) -> Unit,
    brightness: Float?,
    onChooseBrightness: (Float) -> Unit,
) {
    val palette = LocalStoryArcPalette.current

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.xl),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            AdjustmentSlider(
                labelRes = R.string.reader_adjust_brightness,
                value = adjustments.brightness,
                range = -1f..1f,
            ) { onChange(adjustments.copy(brightness = it)) }

            AdjustmentSlider(
                labelRes = R.string.reader_adjust_contrast,
                value = adjustments.contrast,
                range = -1f..1f,
            ) { onChange(adjustments.copy(contrast = it)) }

            // D9: a runtime shader draws this on API 33 and a CPU convolution draws it
            // below that (see `Bitmap.sharpened`), so the control is available on every
            // version this app supports rather than hidden on the two that cannot shade.
            AdjustmentSlider(
                labelRes = R.string.reader_adjust_sharpness,
                value = adjustments.sharpness,
                range = 0f..1f,
            ) { onChange(adjustments.copy(sharpness = it)) }

            MatteSwatches(current = matte, onChoose = onChooseMatte)

            AdjustmentSlider(
                labelRes = R.string.reader_brightness,
                value = brightnessInForce(brightness, LocalContext.current.contentResolver),
                range = 0.1f..1f,
                onChange = onChooseBrightness,
            )

            AdjustmentSwitch(
                labelRes = R.string.reader_adjust_greyscale,
                checked = adjustments.isGreyscale,
            ) { onChange(adjustments.copy(isGreyscale = it)) }

            AdjustmentSwitch(
                labelRes = R.string.reader_adjust_invert,
                checked = adjustments.isInverted,
            ) { onChange(adjustments.copy(isInverted = it)) }

            AdjustmentSwitch(
                labelRes = R.string.reader_adjust_crop,
                noteRes = R.string.reader_adjust_crop_note,
                checked = adjustments.cropsBorders,
            ) { onChange(adjustments.copy(cropsBorders = it)) }

            // `comic-reader`: "the user can disable it for a page that crops wrongly". Only
            // where there is a trim to disable, and about *this* page.
            if (adjustments.cropsBorders) {
                AdjustmentSwitch(
                    labelRes = R.string.reader_adjust_crop_this_page,
                    checked = cropsThisPage,
                    onChange = onCropThisPage,
                )
            }

            // Named, because `comic-reader` requires the change to apply "to the series and
            // [not be] applied globally", and a reader cannot tell that from the controls.
            Text(
                text = stringResource(R.string.reader_adjust_scope, shelf),
                style = MaterialTheme.typography.labelLarge,
                color = palette.textTertiary,
            )

            TextButton(
                onClick = { onChange(ImageAdjustments()) },
                enabled = !adjustments.isNeutral,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = stringResource(R.string.reader_adjust_reset),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun AdjustmentSlider(
    labelRes: Int,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(labelRes),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = "${(value * 100).roundToInt()}%",
                style = MaterialTheme.typography.labelLarge,
                color = palette.textSecondary,
            )
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = range,
            // At zero — which is where all three of these rest — Material's gap leaves the
            // handle floating beside a rail it is not touching. See `StoryArcSliderTrack`.
            track = { state -> StoryArcSliderTrack(state) },
        )
    }
}

@Composable
private fun AdjustmentSwitch(
    labelRes: Int,
    checked: Boolean,
    noteRes: Int? = null,
    onChange: (Boolean) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = StoryArcSpace.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = stringResource(labelRes),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
            )
            noteRes?.let {
                Text(
                    text = stringResource(it),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )
            }
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

/**
 * The colour behind the page, read live rather than read as a default.
 *
 * `app.storyarc.feature.settings`'s own swatches apply the same rule to the global default;
 * these apply it to the shelf that is actually open. Peer feature modules, so this mirrors
 * the grid rather than sharing it -- the same choice [matting] makes for the rule itself.
 */
@Composable
private fun MatteSwatches(current: String?, onChoose: (String?) -> Unit) {
    val palette = LocalStoryArcPalette.current
    Column {
        Text(
            text = stringResource(R.string.reader_matte),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.reader_matte_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
        )
        FlowRow(
            modifier = Modifier.fillMaxWidth().padding(top = StoryArcSpace.xs),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            MatteSwatch(hex = null, isActive = current == null, onChoose = onChoose)
            SUGGESTED_BACKGROUNDS.forEach { hex ->
                MatteSwatch(
                    hex = hex,
                    isActive = current?.equals(hex, ignoreCase = true) == true,
                    onChoose = onChoose,
                )
            }
        }
    }
}

@Composable
private fun MatteSwatch(hex: String?, isActive: Boolean, onChoose: (String?) -> Unit) {
    val palette = LocalStoryArcPalette.current
    val description = hex?.let { matteDescription(it) } ?: stringResource(R.string.reader_matte_none)

    Box(
        modifier = Modifier
            .size(48.dp)
            .selectable(selected = isActive, role = Role.RadioButton, onClick = { onChoose(hex) })
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(30.dp)
                .clip(CircleShape)
                .background(matteColour(hex))
                .border(
                    width = if (isActive) 3.dp else 1.dp,
                    color = if (isActive) palette.accent else palette.borderSubtle,
                    shape = CircleShape,
                ),
        )
    }
}

/**
 * A suggested background's name, or its hex read out as a template if the list ever gains
 * one the catalogue has no word for -- never a bare code, which TalkBack reads one
 * character at a time.
 */
@Composable
internal fun matteDescription(hex: String): String {
    val res = when (SUGGESTED_BACKGROUND_NAMES[hex.uppercase()]) {
        "white" -> R.string.reader_matte_white
        "cream" -> R.string.reader_matte_cream
        "sepia" -> R.string.reader_matte_sepia
        "sage" -> R.string.reader_matte_sage
        "sky" -> R.string.reader_matte_sky
        "charcoal" -> R.string.reader_matte_charcoal
        "navy" -> R.string.reader_matte_navy
        "trueBlack" -> R.string.reader_matte_trueblack
        else -> return stringResource(R.string.reader_matte_swatch, hex)
    }
    return stringResource(res)
}
