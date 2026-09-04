package app.storyarc.feature.reader

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.control.StoryArcSliderTrack
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.ImageAdjustments
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

            // Hidden rather than shown doing nothing: sharpening needs a runtime shader,
            // which arrives in API 33, and StoryArc supports 31.
            if (canSharpen) {
                AdjustmentSlider(
                    labelRes = R.string.reader_adjust_sharpness,
                    value = adjustments.sharpness,
                    range = 0f..1f,
                ) { onChange(adjustments.copy(sharpness = it)) }
            }

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
