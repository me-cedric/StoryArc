package app.storyarc.feature.epubreader

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.control.StoryArcSliderTrack
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.STEPS_PER_AXIS
import app.storyarc.core.model.ThemeAxis
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.sliderRange
import app.storyarc.core.model.unit
import app.storyarc.core.model.value

/**
 * One axis: its name, its stated value, its slider, and the long press, double tap and
 * accessibility action that reset it. Shared by [FineAxes] — the axes hidden under
 * Original — and [MarginsControl], which is not one of them.
 *
 * Split out of `ThemeAxesScreen.kt` because that file sat at its 800-line cap; the seam is
 * the axis itself, since margins needed everything here except the loop.
 */
@Composable
internal fun AxisSlider(
    preset: ThemePreset,
    axis: ThemeAxis,
    range: ClosedRange<Double>,
    values: ThemeValues,
    onSet: (ThemeAxis, Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            // `reading-themes`, *Resetting an axis*: a long press or a double tap
            // returns that axis to its preset value.
            //
            // **On the axis block too, not only on the slider the spec names.**
            // `detectTapGestures` waits on the Main pass, and `Slider` handles the
            // down inside its own node first, so a detector wrapped around the
            // slider never starts here — but a press that lands on the name, the
            // value or the space around them, above the track, has no descendant
            // to consume it first. `AxisSlider`'s own `detectAxisResetGesture`
            // below is what actually reaches the slider itself.
            .pointerInput(axis, preset) {
                detectTapGestures(onLongPress = { resetAxis(preset, axis, onSet) })
            },
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        val spoken = spokenValue(values.value(axis), axis.unit)
        val name = stringResource(axis.labelRes)
        val resetName = stringResource(R.string.theme_axis_reset)

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
            modifier = Modifier
                // The gesture the spec names, on the slider itself. See
                // `detectAxisResetGesture` for why this needs its own
                // `Initial`-pass detector rather than `detectTapGestures`.
                .pointerInput(axis, preset) {
                    detectAxisResetGesture { resetAxis(preset, axis, onSet) }
                }
                .semantics {
                    contentDescription = name
                    stateDescription = spoken
                    // The reset, without the gesture. TalkBack, Switch Access and a
                    // keyboard cannot long-press, and `native-experience` requires a
                    // control to announce what it does.
                    customActions = listOf(
                        CustomAccessibilityAction(resetName) {
                            resetAxis(preset, axis, onSet)
                            true
                        },
                    )
                },
        )
    }
}

/**
 * Margins alone, effective — and drawn — under every preset including Original.
 * `ThemeAxesScreen` shows this regardless of `keepsPublisherStyles`, unlike [FineAxes]:
 * `ThemeAxis.requiresPublisherStylesOff` puts margins with font size, family and weight,
 * on the side Readium honours whatever `publisherStyles` is set to.
 */
@Composable
internal fun MarginsControl(
    preset: ThemePreset,
    values: ThemeValues,
    onSet: (ThemeAxis, Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    val range = ThemeAxis.MARGINS.sliderRange ?: return
    AxisSlider(preset, ThemeAxis.MARGINS, range, values, onSet, modifier)
}
